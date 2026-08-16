#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results/

# 2. Reference indexing (once)
if [ ! -f data/ref/chrM.fa.fai ] || [ ! -f data/ref/chrM.fa.amb ]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

# 3-7. Per-sample processing
for sample in "${SAMPLES[@]}"; do
    if [ -f "results/${sample}.vcf.gz.tbi" ]; then
        continue
    fi

    # Alignment & sorting
    bwa mem -t ${THREADS} -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        data/ref/chrM.fa "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ ${THREADS} -o "results/${sample}.bam"

    # BAM indexing
    samtools index -@ ${THREADS} "results/${sample}.bam"

    # Variant calling
    lofreq call-parallel --pp-threads ${THREADS} \
        -f data/ref/chrM.fa -r "results/${sample}.bam" -o "results/${sample}.vcf"

    # VCF compression & indexing
    bgzip "results/${sample}.vcf"
    tabix -p vcf "results/${sample}.vcf.gz"

    rm -f "results/${sample}.vcf"
done

# 8. Collapse step
if [ ! -f results/collapsed.tsv ]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
            "results/${sample}.vcf.gz" >> results/collapsed.tsv
    done
fi