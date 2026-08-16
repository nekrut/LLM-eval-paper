#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RES_DIR="results"

mkdir -p "$RES_DIR"

# 2. Reference indexing (idempotent)
if [[ ! -f "${REF}.fai" ]] || [[ ! -f "${REF}.bwt" ]]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="${RES_DIR}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${RES_DIR}/${SAMPLE}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    # Check if all final artifacts for this sample exist and are up-to-date
    # We check the newest artifact (TBI) against the BAM and VCF_GZ
    if [[ -f "$TBI" ]] && [[ "$TBI" -nt "$BAM" ]] && [[ "$TBI" -nt "$VCF_GZ" ]]; then
        continue
    fi

    # 3 & 4. Alignment and Sorting
    # bwa mem with read group, piped to samtools sort
    RG="@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA"
    bwa mem -t "$THREADS" -R "$RG" "$REF" \
        "${RAW_DIR}/${SAMPLE}_1.fq.gz" \
        "${RAW_DIR}/${SAMPLE}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "$BAM"

    # 5. BAM indexing
    samtools index -@ "$THREADS" "$BAM"

    # 6. Variant calling with lofreq call-parallel
    VCF_TMP="${RES_DIR}/${SAMPLE}.vcf"
    lofreq call-parallel \
        --ref "$REF" \
        --pp-threads "$THREADS" \
        -o "$VCF_TMP" \
        "$BAM"

    # 7. VCF compression and indexing
    bgzip -c "$VCF_TMP" > "$VCF_GZ"
    tabix -p vcf "$VCF_GZ"
    rm -f "$VCF_TMP"
done

# 8. Collapse step -> results/collapsed.tsv
COLLAPSED="${RES_DIR}/collapsed.tsv"
NEED_REBUILD=false

# Check if collapsed.tsv exists and is newer than all input VCFs
if [[ ! -f "$COLLAPSED" ]]; then
    NEED_REBUILD=true
else
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${RES_DIR}/${SAMPLE}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$COLLAPSED" ]]; then
            NEED_REBUILD=true
            break
        fi
    done
fi

if $NEED_REBUILD; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for SAMPLE in "${SAMPLES[@]}"; do
            VCF_GZ="${RES_DIR}/${SAMPLE}.vcf.gz"
            bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ"
        done
    } > "$COLLAPSED"
fi