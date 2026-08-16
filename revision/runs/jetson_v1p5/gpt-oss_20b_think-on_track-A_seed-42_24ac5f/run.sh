#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Check if all expected outputs already exist; exit if so
all_done=true
for sample in "${SAMPLES[@]}"; do
    [[ ! -f "results/${sample}.bam" ]] && all_done=false
    [[ ! -f "results/${sample}.bam.bai" ]] && all_done=false
    [[ ! -f "results/${sample}.vcf.gz" ]] && all_done=false
    [[ ! -f "results/${sample}.vcf.gz.tbi" ]] && all_done=false
done
[[ -f results/collapsed.tsv ]] || all_done=false

if $all_done; then
    exit 0
fi

# Create output directory if needed
mkdir -p results

# Reference indexing (BWA and samtools)
if [[ ! -f data/ref/chrM.fa.bwt || ! -f data/ref/chrM.fa.fai ]]; then
    bwa index data/ref/chrM.fa
    samtools faidx data/ref/chrM.fa
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    bai="${bam}.bai"

    # Alignment and BAM indexing
    if [[ ! -f "$bam" || ! -f "$bai" ]]; then
        bwa mem -t $THREADS \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            data/raw/${sample}_1.fq.gz \
            data/raw/${sample}_2.fq.gz | \
        samtools sort -@ $THREADS -o "$bam" -
        samtools index -@ $THREADS "$bam"
    fi

    # Variant calling with LoFreq
    vcf="${sample}.vcf"
    vcf_gz="results/${sample}.vcf.gz"
    tbi="${vcf_gz}.tbi"

    if [[ ! -f "$vcf_gz" || ! -f "$tbi" ]]; then
        lofreq call-parallel --pp-threads $THREADS \
            -f data/ref/chrM.fa \
            -o "results/${vcf}" \
            "$bam"
        bgzip -f "results/${vcf}"
        tabix -p vcf "$vcf_gz"
    fi
done

# Generate collapsed.tsv
printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz" |
        awk -v s="$sample" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv
done

exit 0