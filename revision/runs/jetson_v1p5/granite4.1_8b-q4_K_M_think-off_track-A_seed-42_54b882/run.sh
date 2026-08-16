#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

# Reference indexing (BWA)
bwa index data/ref/chrM.fa

# Reference indexing (samtools faidx)
samtools faidx data/ref/chrM.fa

for sample in "${SAMPLES[@]}"; do
    # Alignment and sorting
    bwa mem -t ${THREADS} \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        data/ref/chrM.fa \
        data/raw/${sample}_1.fq.gz \
        data/raw/${sample}_2.fq.gz |
    samtools sort -@ ${THREADS} -o results/${sample}.bam -

    # BAM indexing
    samtools index -@ ${THREADS} results/${sample}.bam

    # Variant calling with LoFreq
    lofreq call-parallel --pp-threads ${THREADS} \
        -f data/ref/chrM.fa \
        -o results/${sample}.vcf \
        results/${sample}.bam

    # VCF compression and tabix indexing
    bgzip -f results/${sample}.vcf
    tabix -p vcf results/${sample}.vcf.gz

    # Append sample-specific header line to collapsed TSV (if not already present)
    if ! grep -q "^${sample}\t" results/collapsed.tsv; then
        printf '%s\t%s\n' "${sample}" "$(head -n 1 results/${sample}.vcf.gz | cut -f 1-5)" >> results/collapsed.tsv
    fi

    # Append variant lines to collapsed TSV
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
        results/${sample}.vcf.gz |
    awk -v s=${sample} 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done

# Ensure collapsed TSV has proper header (only if first line is not the header)
if ! grep -q '^sample\tchrom\tpos\tref\talt\taf$' results/collapsed.tsv; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
    cat results/collapsed.tsv >> results/collapsed.tsv
    mv results/collapsed.tsv.tmp results/collapsed.tsv
fi

exit 0