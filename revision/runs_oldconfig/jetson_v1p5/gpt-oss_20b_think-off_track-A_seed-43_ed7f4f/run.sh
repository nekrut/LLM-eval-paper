#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

# Reference indexing
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
    bam=results/${sample}.bam
    bai=${bam}.bai
    vcf_gz=results/${sample}.vcf.gz

    if [ ! -s "$bam" ]; then
        bwa mem -t $THREADS -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            data/raw/${sample}_1.fq.gz \
            data/raw/${sample}_2.fq.gz | \
        samtools sort -@ $THREADS -o "$bam" -
    fi

    if [ ! -s "$bai" ]; then
        samtools index -@ $THREADS "$bam"
    fi

    if [ ! -s "$vcf_gz" ]; then
        lofreq call-parallel --pp-threads $THREADS -f data/ref/chrM.fa -o results/${sample}.vcf "$bam"
        bgzip -f results/${sample}.vcf
        tabix -p vcf results/${sample}.vcf.gz
    fi
done

collapsed=results/collapsed.tsv
if [ ! -s "$collapsed" ]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed"
    for sample in "${SAMPLES[@]}"; do
        vcf_gz=results/${sample}.vcf.gz
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_gz" | \
            awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> "$collapsed"
    done
fi

exit 0