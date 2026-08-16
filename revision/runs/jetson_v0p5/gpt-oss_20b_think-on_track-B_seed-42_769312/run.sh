#!/usr/bin/env bash
set -euo pipefail

THREADS=4

mkdir -p results

# Index reference if not already indexed
if ! [ -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${samples[@]}"; do
    bam=results/${sample}.bam
    bai=results/${sample}.bam.bai
    vcf_gz=results/${sample}.vcf.gz
    vcf_tbi=results/${sample}.vcf.gz.tbi

    # Map reads if BAM not present
    if ! [ -f "$bam" ]; then
        bwa mem -t $THREADS data/ref/chrM.fa data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz | \
            samtools view -bS - | samtools sort -o "$bam"
    fi

    # Index BAM if index missing
    if ! [ -f "$bai" ]; then
        samtools index "$bam"
    fi

    # Call variants if VCF not present
    if ! [ -f "$vcf_gz" ]; then
        lofreq call -f data/ref/chrM.fa -o - "$bam" | \
            bcftools view -O z -o "$vcf_gz"
        tabix -p vcf "$vcf_gz"
    fi
done

# Generate collapsed table if not present
collapsed=results/collapsed.tsv
if ! [ -f "$collapsed" ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed"
    for sample in "${samples[@]}"; do
        vcf_gz=results/${sample}.vcf.gz
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n' "$vcf_gz" | \
            awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> "$collapsed"
    done
fi

exit 0