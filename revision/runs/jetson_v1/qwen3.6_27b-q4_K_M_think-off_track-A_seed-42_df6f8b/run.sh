#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

# 2. Reference indexing (idempotent)
if [[ ! -f "${REF}.fai" ]] || [[ ! -f "${REF}.bwt" ]]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="${OUT_DIR}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
    TBI="${VCF_GZ}.tbi"
    VCF_TMP="${OUT_DIR}/${SAMPLE}.vcf"

    # Check if final artifacts exist and are up-to-date
    # We consider the sample done if the .tbi exists and is newer than the raw FASTQs
    F1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    F2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    if [[ -f "$TBI" ]] && [[ "$TBI" -nt "$F1" ]] && [[ "$TBI" -nt "$F2" ]]; then
        continue
    fi

    # 3 & 4. Alignment and Sorting
    # bwa mem with read group, piped to samtools sort
    RG="@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA"
    
    if [[ ! -f "$BAM" ]] || [[ "$F1" -nt "$BAM" ]] || [[ "$F2" -nt "$BAM" ]]; then
        bwa mem -t "$THREADS" -R "$RG" "$REF" "$F1" "$F2" | \
            samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    # 5. BAM Indexing
    if [[ ! -f "$BAI" ]] || [[ "$BAM" -nt "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # 6. Variant Calling with lofreq call-parallel
    # Output to temporary uncompressed VCF
    if [[ ! -f "$VCF_GZ" ]] || [[ "$BAI" -nt "$VCF_GZ" ]]; then
        lofreq call-parallel \
            --pp-threads "$THREADS" \
            -f "$REF" \
            -o "$VCF_TMP" \
            "$BAM"
    fi

    # 7. VCF Compression and Indexing
    if [[ ! -f "$TBI" ]] || [[ "$VCF_TMP" -nt "$TBI" ]]; then
        bgzip -c "$VCF_TMP" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm -f "$VCF_TMP"
    fi
done

# 8. Collapse step -> results/collapsed.tsv
COLLAPSED="${OUT_DIR}/collapsed.tsv"
NEED_COLLAPSE=false

if [[ ! -f "$COLLAPSED" ]]; then
    NEED_COLLAPSE=true
else
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$COLLAPSED" ]]; then
            NEED_COLLAPSE=true
            break
        fi
    done
fi

if $NEED_COLLAPSE; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for SAMPLE in "${SAMPLES[@]}"; do
            VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
            bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ"
        done
    } > "$COLLAPSED"
fi