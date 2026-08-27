#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Reference indexing with BWA
[[ -f data/ref/chrM.fa.bwt ]] || bwa index data/ref/chrM.fa

# Reference indexing with samtools faidx
[[ -f data/ref/chrM.fa.fai ]] || samtools faidx data/ref/chrM.fa

for sample in "${SAMPLES[@]}"; do
    # Alignment and sorting to BAM
    bam=results/${sample}.bam
    [[ -f "$bam" ]] || {
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
        samtools sort -@ "$THREADS" -o "$bam" -
    }

    # BAM index
    bai=results/${sample}.bam.bai
    [[ -f "$bai" ]] || samtools index -@ "$THREADS" "$bam"

    # Variant calling with LoFreq
    vcf_uncompressed=results/${sample}.vcf
    if ! [[ -f "$vcf_uncompressed" && -s "$vcf_uncompressed" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" \
            -f data/ref/chrM.fa -o "$vcf_uncompressed" "$bam"
    fi

    # Compress and index VCF
    vcf_gz=results/${sample}.vcf.gz
    tbi=results/${sample}.vcf.gz.tbi
    [[ -f "$tbi" ]] || {
        bgzip -f "$vcf_uncompressed"
        tabix -p vcf "$vcf_gz"
    }
done

# Build collapsed TSV
printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
        results/${sample}.vcf.gz |
    awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done