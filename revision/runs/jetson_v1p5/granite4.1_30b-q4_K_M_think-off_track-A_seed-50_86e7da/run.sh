#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

# Reference indexing (idempotent)
if [[ ! -f data/ref/chrM.fa.bwt ]]; then
    bwa index data/ref/chrM.fa
fi
if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    vcf="results/${sample}.vcf.gz"

    # Skip if final VCF already exists (idempotent)
    if [[ -f "$vcf" && -f "$vcf.tbi" ]]; then
        continue
    fi

    # 3. Alignment + sort
    bwa mem -t "${THREADS}" \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        data/ref/chrM.fa \
        data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
    samtools sort -@ "${THREADS}" -o "$bam" -

    # 4. Index BAM
    samtools index -@ "${THREADS}" "$bam"

    # 5. Variant calling with LoFreq (produces uncompressed VCF)
    lofreq call-parallel --pp-threads "${THREADS}" \
        -f data/ref/chrM.fa -o "results/${sample}.vcf" "$bam"

    # 6. Compress and tabix index VCF
    bgzip -f "results/${sample}.vcf"
    tabix -p vcf "results/${sample}.vcf.gz"

    # 7a. Initialize collapsed TSV (only once)
    if [[ ! -f results/collapsed.tsv ]]; then
        printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
    fi

    # 7b. Append variants for this sample
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz" |
        awk -v s="${sample}" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done