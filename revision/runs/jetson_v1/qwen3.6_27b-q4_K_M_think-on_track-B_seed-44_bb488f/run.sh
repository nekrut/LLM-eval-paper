#!/usr/bin/env bash
set -euo pipefail

REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"
THREADS="${THREADS:-4}"

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p "$OUT_DIR"

# Index reference if needed
[[ -f "${REF}.bwt" ]] || bwa index "$REF"
[[ -f "${REF}.fai" ]] || samtools faidx "$REF"

for SAMPLE in "${SAMPLES[@]}"; do
    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"
    BAM="${OUT_DIR}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    # Idempotency: skip if all outputs exist
    [[ -f "$BAM" && -f "$BAI" && -f "$VCF_GZ" && -f "$TBI" ]] && continue

    # Align with bwa mem
    bwa mem -t "$THREADS" "$REF" "$R1" "$R2" | \
        samtools view -b -@ "$THREADS" -o "${BAM}.tmp"

    # Sort BAM
    samtools sort -@ "$THREADS" "${BAM}.tmp" -o "$BAM"
    rm -f "${BAM}.tmp"

    # Index BAM
    samtools index "$BAM"

    # Variant calling with bcftools mpileup + call
    bcftools mpileup -f "$REF" -Ou "$BAM" | \
        bcftools call -mv -Oz -o "$VCF_GZ"

    # Index VCF
    tabix -p vcf "$VCF_GZ"
done

# Create collapsed.tsv from all sample VCFs (only if not present)
if [[ ! -f "${OUT_DIR}/collapsed.tsv" ]]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for SAMPLE in "${SAMPLES[@]}"; do
            VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT[\t%INFO/AF]\n' "$VCF_GZ" | \
                awk -v s="$SAMPLE" '{print s"\t"$0}'
        done
    } > "${OUT_DIR}/collapsed.tsv"
fi