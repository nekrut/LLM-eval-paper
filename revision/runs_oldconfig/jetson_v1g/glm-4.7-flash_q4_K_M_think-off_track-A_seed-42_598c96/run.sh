#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
RAW_DIR="data/raw"
REF_DIR="data/ref"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# 2. Reference indexing (once)
if [[ ! -f "$REF_DIR/chrM.fa.fai" ]]; then
    samtools faidx "$REF_DIR/chrM.fa"
fi
if [[ ! -f "$REF_DIR/chrM.fa.bwt" ]]; then
    bwa index "$REF_DIR/chrM.fa"
fi

# 3. Per-sample alignment with bwa mem
for sample in "${SAMPLES[@]}"; do
    bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        "$REF_DIR/chrM.fa" "$RAW_DIR/${sample}_1.fq.gz" "$RAW_DIR/${sample}_2.fq.gz" \
        | samtools sort -@ "$THREADS" -o "$RESULTS_DIR/${sample}.bam"
done

# 5. BAM indexing
for sample in "${SAMPLES[@]}"; do
    samtools index -@ "$THREADS" "$RESULTS_DIR/${sample}.bam"
done

# 6. Variant calling with lofreq call-parallel
for sample in "${SAMPLES[@]}"; do
    lofreq call-parallel --pp-threads "$THREADS" --verbose \
        --ref "$REF_DIR/chrM.fa" --out "$RESULTS_DIR/${sample}.vcf" \
        --sig --bonf \
        "$RESULTS_DIR/${sample}.bam"
done

# 7. VCF compression and indexing
for sample in "${SAMPLES[@]}"; do
    bgzip -c "$RESULTS_DIR/${sample}.vcf" > "$RESULTS_DIR/${sample}.vcf.gz"
    tabix -p vcf "$RESULTS_DIR/${sample}.vcf.gz"
    rm "$RESULTS_DIR/${sample}.vcf"
done

# 8. Collapse step -> results/collapsed.tsv
COLLAPSED_FILE="$RESULTS_DIR/collapsed.tsv"
HEADER="sample\tchrom\tpos\tref\talt\taf"

# Check if any input VCF is newer than the TSV
if [[ ! -f "$COLLAPSED_FILE" ]] || \
   find "$RESULTS_DIR" -name "*.vcf.gz" -newer "$COLLAPSED_FILE" | grep -q .; then
    {
        echo -e "$HEADER"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$RESULTS_DIR/${sample}.vcf.gz"
        done
    } > "$COLLAPSED_FILE"
fi