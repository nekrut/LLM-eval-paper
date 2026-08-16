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

    # Check if final artifacts exist and are up-to-date
    # We consider the sample done if the .tbi exists and is newer than the input FASTQs
    FQ1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    FQ2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    if [[ -f "$TBI" ]] && [[ "$TBI" -nt "$FQ1" ]] && [[ "$TBI" -nt "$FQ2" ]]; then
        continue
    fi

    # 3 & 4. Alignment and sorting
    # Note: The prompt requires literal backslash-t in the RG string for bwa mem -R
    RG="-R \"@RG\\tID:${SAMPLE}\\tSM:${SAMPLE}\\tLB:${SAMPLE}\\tPL:ILLUMINA\""

    bwa mem -t "$THREADS" "$REF" "$FQ1" "$FQ2" $RG | \
        samtools sort -@ "$THREADS" -o "$BAM" -

    # 5. BAM indexing
    samtools index -@ "$THREADS" "$BAM"

    # 6. Variant calling with lofreq
    VCF_TMP="${OUT_DIR}/${SAMPLE}.vcf"
    lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF_TMP" "$BAM"

    # 7. VCF compression and indexing
    bgzip -c "$VCF_TMP" > "$VCF_GZ"
    tabix -p vcf "$VCF_GZ"
    rm -f "$VCF_TMP"
done

# 8. Collapse step -> results/collapsed.tsv
TSV="${OUT_DIR}/collapsed.tsv"
NEED_REBUILD=false

if [[ ! -f "$TSV" ]]; then
    NEED_REBUILD=true
else
    # Check if any VCF is newer than the TSV
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$TSV" ]]; then
            NEED_REBUILD=true
            break
        fi
    done
fi

if $NEED_REBUILD; then
    # Create header
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$TSV"

    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$TSV"
    done
fi