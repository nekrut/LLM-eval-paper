#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

REF="data/ref/chrM.fa"

if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

sample_exists() {
    local s="$1"
    [[ -f "results/${s}.bam" && -f "results/${s}.bam.bai" &&
       -f "results/${s}.vcf.gz" && -f "results/${s}.vcf.gz.tbi" ]]
}

for s in "${SAMPLES[@]}"; do
    if sample_exists "$s"; then
        continue
    fi

    bam="results/${s}.bam"
    bwa mem -t "$THREADS" -R "@RG\tID:${s}\tSM:${s}\tLB:${s}\tPL:ILLUMINA" \
        "$REF" "data/raw/${s}_1.fq.gz" "data/raw/${s}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "$bam" -

    samtools index -@ "$THREADS" "$bam"

    lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "results/${s}.vcf" "$bam"

    bgzip -f "results/${s}.vcf"
    tabix -p vcf "results/${s}.vcf.gz"
done

ALL_OK=true
for s in "${SAMPLES[@]}"; do
    if ! sample_exists "$s"; then
        ALL_OK=false
        break
    fi
done
if [ ! -f results/collapsed.tsv ]; then
    ALL_OK=false
fi

if $ALL_OK; then
    exit 0
fi

COLLAPSED="results/collapsed.tsv"
printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$COLLAPSED"

for s in "${SAMPLES[@]}"; do
    vcf_gz="results/${s}.vcf.gz"
    if [ ! -f "$vcf_gz" ]; then
        continue
    fi
    while IFS=$'\t' read -r chrom pos ref alt af; do
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$s" "$chrom" "$pos" "$ref" "$alt" "$af"
    done < <(bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_gz") >> "$COLLAPSED"
done