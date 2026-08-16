#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

# 2. Reference indexing
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

# 3-7. Per-sample processing
for SAMPLE in "${SAMPLES[@]}"; do
    R1="data/raw/${SAMPLE}_1.fq.gz"
    R2="data/raw/${SAMPLE}_2.fq.gz"
    BAM="${OUT_DIR}/${SAMPLE}.bam"
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
    VCF_TBI="${OUT_DIR}/${SAMPLE}.vcf.gz.tbi"

    # Check if all outputs exist and are newer than inputs
    if [[ -f "$VCF_TBI" && "$VCF_TBI" -nt "$R1" && "$VCF_TBI" -nt "$R2" ]]; then
        continue
    fi

    # 3-4. Alignment and Sorting
    RG="@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA"
    bwa mem -t "$THREADS" -R "$RG" "$REF" "$R1" "$R2" | \
        samtools sort -@ "$THREADS" -o "$BAM"

    # 5. BAM Indexing
    if [[ ! -f "${BAM}.bai" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # 6. Variant calling with lofreq
    VCF_TMP="${OUT_DIR}/${SAMPLE}.vcf"
    if [[ ! -f "$VCF_GZ" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" "$BAM" > "$VCF_TMP"
        
        # 7. Compression and Indexing
        bgzip -c "$VCF_TMP" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "$VCF_TMP"
    fi
done

# 8. Collapse step
TSV_OUT="${OUT_DIR}/collapsed.tsv"
NEEDS_COLLAPSE=false

if [[ ! -f "$TSV_OUT" ]]; then
    NEEDS_COLLAPSE=true
else
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$TSV_OUT" ]]; then
            NEEDS_COLLAPSE=true
            break
        fi
    done
fi

if [ "$NEEDS_COLLAPSE" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$TSV_OUT"
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$TSV_OUT"
    done
fi

exit 0