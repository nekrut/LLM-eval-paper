#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

REF=data/ref/chrM.fa

if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi

if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

process_sample() {
    local sample="$1"
    local bam=results/"$sample".bam
    local bai=results/"$sample".bam.bai
    local vcf_gz=results/"$sample".vcf.gz
    local tbi=results/"$sample".vcf.gz.tbi

    if [ -f "$bam" ] && [ -f "$bai" ] && [ -f "$vcf_gz" ] && [ -f "$tbi" ]; then
        return 0
    fi

    bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        "$REF" data/raw/"${sample}"_1.fq.gz data/raw/"${sample}"_2.fq.gz | \
        samtools sort -@ "$THREADS" -o "$bam" -

    samtools index -@ "$THREADS" "$bam"

    lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o results/"$sample".vcf "$bam"

    bgzip -f results/"$sample".vcf

    tabix -p vcf "$vcf_gz"
}

for s in "${SAMPLES[@]}"; do
    process_sample "$s"
done

COLLAPSED=results/collapsed.tsv
printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$COLLAPSED"

for s in "${SAMPLES[@]}"; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' results/"$s".vcf.gz | \
        while IFS= read -r line; do printf '%s\t%s\n' "$s" "$line"; done >> "$COLLAPSED"
done

exit 0