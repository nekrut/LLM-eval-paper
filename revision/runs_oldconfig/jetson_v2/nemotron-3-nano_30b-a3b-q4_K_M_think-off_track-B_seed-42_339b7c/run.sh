#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

# Index reference if not already indexed
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

# Process each sample
for sample_dir in data/raw/*; do
    base=$(basename "$sample_dir")
    sample="${base%_1.fq.gz}"
    
    # Skip if output files already exist (idempotency)
    if [ -f "results/${sample}.bam" ] && [ -f "results/${sample}.bam.bai" ]; then
        continue
    fi

    r1="${sample_dir}_1.fq.gz"
    r2="${sample_dir}_2.fq.gz"

    # Align with BWA-MEM
    bwa mem -t 4 data/ref/chrM.fa "$r1" "$r2" | samtools view -@ 4 -b - > "results/${sample}.bam"
    
    # Sort and index
    samtools sort -o "results/${sample}.sorted.bam" "results/${sample}.bam"
    samtools index "results/${sample}.sorted.bam"
    mv "results/${sample}.sorted.bam" "results/${sample}.bam"
    cp "results/${sample}.bam.bai" "results/${sample}.bam.bai"

    # Variant calling with lofreq
    lofreq call --ref data/ref/chrM.fa \
        --aligned "$(printf '%.0s%s,' {1..4} "${sample}_*.bam")" \
        --output results/${sample}.vcf.gz

    # Index VCF
    bcftools index "results/${sample}.vcf.gz"
done

# Collapse VCFs into TSV with SnpSift
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample_dir in data/raw/*; do
        base=$(basename "$sample_dir")
        sample="${base%_1.fq.gz}"
        vcf="results/${sample}.vcf.gz"
        if [ -f "$vcf" ]; then
            zcat "$vcf" | \
                SnpSift extractFields -samples ${sample} \
                    -fields CHROM, POS, REF, ALT, INFO/AF \
                    -header | \
                awk 'BEGIN{OFS="\t"} {print "'"$sample"'", $1, $2, $3, $4, $5}' 
        fi
    done
} > results/collapsed.tsv

# Ensure collapsed.tsv has proper header and format
if [ -f "results/collapsed.tsv" ]; then
    # Rebuild with correct structure if needed (idempotent)
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample_dir in data/raw/*; do
            base=$(basename "$sample_dir")
            sample="${base%_1.fq.gz}"
            vcf="results/${sample}.vcf.gz"
            if [ -f "$vcf" ]; then
                zcat "$vcf" | \
                    SnpSift extractFields -samples ${sample} \
                        -fields CHROM, POS, REF, ALT, INFO/AF \
                        -header | \
                    awk -v s="$sample" 'BEGIN{OFS="\t"} {print s, $1, $2, $3, $4, $5}'
            fi
        done
    } > results/collapsed.tsv.tmp && mv results/collapsed.tsv.tmp results/collapsed.tsv
fi

exit 0