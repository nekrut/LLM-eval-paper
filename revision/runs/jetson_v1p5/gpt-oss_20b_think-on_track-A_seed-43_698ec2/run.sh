#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Reference indexing with BWA if not already indexed
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

# Reference indexing with samtools faidx if not already indexed
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
    bam=results/${sample}.bam
    bai=${bam}.bai
    vcf_gz=results/${sample}.vcf.gz

    # Alignment and sorting if BAM missing
    if [ ! -f "$bam" ]; then
        bwa mem -t $THREADS -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
            samtools sort -@ $THREADS -o "$bam" -
    fi

    # Index BAM if missing
    if [ ! -f "$bai" ]; then
        samtools index -@ $THREADS "$bam"
    fi

    # Variant calling with LoFreq and compression if VCF.gz missing
    if [ ! -f "$vcf_gz" ]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa \
            -o results/${sample}.vcf "$bam"
        bcftools view -Oz -o "$vcf_gz" results/${sample}.vcf
        rm results/${sample}.vcf
        tabix -p vcf "$vcf_gz"
    fi
done

# Create collapsed.tsv header if not present
collapsed=results/collapsed.tsv
if [ ! -f "$collapsed" ]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed"
fi

# Append per-sample variant data, avoiding duplicates
for sample in "${SAMPLES[@]}"; do
    vcf_gz=results/${sample}.vcf.gz
    if ! grep -q "^${sample}[\t]" "$collapsed"; then
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_gz" |
            awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> "$collapsed"
    fi
done

exit 0