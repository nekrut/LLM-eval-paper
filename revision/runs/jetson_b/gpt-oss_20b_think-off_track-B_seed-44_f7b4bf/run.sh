#!/usr/bin/env bash
set -euo pipefail

RAW_DIR="data/raw"
REF_DIR="data/ref"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

REF_FASTA="$REF_DIR/chrM.fa"

# Index reference if needed
if ! ls "${REF_FASTA}.bwt" 1>/dev/null 2>&1; then
    bwa index "$REF_FASTA"
fi

# Gather sample names from raw data
SAMPLES=()
for f in "$RAW_DIR"/*_1.fq.gz; do
    base=$(basename "$f")
    sample=${base%_1.fq.gz}
    SAMPLES+=("$sample")
done

map_sample() {
    local sample=$1
    local r1="$RAW_DIR/${sample}_1.fq.gz"
    local r2="$RAW_DIR/${sample}_2.fq.gz"
    local bam="${OUT_DIR}/${sample}.bam"

    if [[ -f "$bam" && -f "${bam}.bai" ]]; then
        return 0
    fi

    bwa mem -t 4 "$REF_FASTA" "$r1" "$r2" | \
        samtools view -Sb - | \
        samtools sort -o "$bam"

    samtools index "$bam"
}

call_variants() {
    local sample=$1
    local bam="${OUT_DIR}/${sample}.bam"
    local vcf_gz="${OUT_DIR}/${sample}.vcf.gz"

    if [[ -f "$vcf_gz" && -f "${vcf_gz}.tbi" ]]; then
        return 0
    fi

    lofreq call -f "$REF_FASTA" -o "$vcf_gz" "$bam"
    tabix -p vcf "$vcf_gz"
}

for s in "${SAMPLES[@]}"; do
    map_sample "$s"
    call_variants "$s"
done

COLLAPSED="$OUT_DIR/collapsed.tsv"

if [[ ! -f "$COLLAPSED" ]]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for s in "${SAMPLES[@]}"; do
        vcf="${OUT_DIR}/${s}.vcf.gz"
        while IFS=$'\t' read -r chrom pos ref alt af; do
            printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$s" "$chrom" "$pos" "$ref" "$alt" "$af"
        done < <(bcftools query -f '%CHROM%\t%POS%\t%REF%\t%ALT%\t[%AF]\n' "$vcf")
    done
fi

exit 0