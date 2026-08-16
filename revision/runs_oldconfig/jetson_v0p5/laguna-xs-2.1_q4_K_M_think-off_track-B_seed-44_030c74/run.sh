#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"

mkdir -p results

# Index reference if not already indexed
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    bam="${sample}.bam"
    vcf_gz="${sample}.vcf.gz"
    
    # Skip if all outputs exist and are non-empty
    if [[ -s "results/${bam}" && -s "results/${bam}.bai" && -s "results/${vcf_gz}" && -s "results/${vcf_gz}.tbi" ]]; then
        continue
    fi
    
    # Align reads
    bwa mem -t "$THREADS" "$REF" "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
    samtools view -bS - | \
    samtools sort -@ "$THREADS" -o "results/${bam}" -
    
    # Index BAM
    samtools index "results/${bam}"
    
    # Mark duplicates and base quality recalibration with lofreq
    lofreq markduplicates -r "$REF" -f "results/${bam}" -o "results/${sample}_dedup.bam"
    
    # Call variants with lofreq
    lofreq viterbi -f "$REF" -l 100 -q 20 -Q 20 -s 3 -w 50 -b "results/${sample}_dedup.bam" -o /dev/stdout | \
    bcftools view -Ov - > "results/${sample}.vcf"
    
    # Compress and index VCF
    bcftools view -Oz -o "results/${vcf_gz}" "results/${sample}.vcf"
    tabix -p vcf "results/${vcf_gz}"
    
    rm -f "results/${sample}.vcf" "results/${sample}_dedup.bam"
done

# Create collapsed.tsv with AF from all samples
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="${sample}.vcf.gz"
        if [[ -s "results/${vcf_gz}" ]]; then
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' "results/${vcf_gz}" | \
            awk -v sample="$sample" '{print sample"\t"$1"\t"$2"\t"$3"\t"$4"\t"$5}'
        fi
    done > results/collapsed.tsv.tmp
    
    # Sort and deduplicate by sample, chrom, pos, ref, alt
    sort -u -k1,1 -k2,2n -k3,3 -k4,4 -k5,5 results/collapsed.tsv.tmp > results/collapsed.tsv
    rm -f results/collapsed.tsv.tmp
}

exit 0