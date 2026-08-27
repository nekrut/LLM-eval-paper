#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW="data/raw"
RESULTS="results"

mkdir -p "$RESULTS"

# 2. Reference indexing (once)
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

# 3-5. Per-sample alignment, sorting, and indexing
for SAMPLE in "${SAMPLES[@]}"; do
    INPUT1="${RAW}/${SAMPLE}_1.fq.gz"
    INPUT2="${RAW}/${SAMPLE}_2.fq.gz"
    BAM="${RESULTS}/${SAMPLE}.bam"
    BAI="${RESULTS}/${SAMPLE}.bam.bai"

    if [[ -f "$BAI" ]]; then
        continue
    fi

    bwa mem -t "$THREADS" -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" "$REF" "$INPUT1" "$INPUT2" | \
    samtools sort -@ "$THREADS" -o "$BAM"
    samtools index -@ "$THREADS" "$BAM"
done

# 6-7. Variant calling, compression, and indexing
for SAMPLE in "${SAMPLES[@]}"; do
    VCF="${RESULTS}/${SAMPLE}.vcf"
    VCF_GZ="${RESULTS}/${SAMPLE}.vcf.gz"
    VCF_TBI="${RESULTS}/${SAMPLE}.vcf.gz.tbi"

    if [[ -f "$VCF_TBI" ]]; then
        continue
    fi

    lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF" "${RESULTS}/${SAMPLE}.bam"
    bgzip -c "$VCF" > "$VCF_GZ"
    tabix -p vcf "$VCF_GZ"
    rm -f "$VCF"
done

# 8. Collapse step
COLLAPSED="${RESULTS}/collapsed.tsv"
HEADER="sample\tchrom\tpos\tref\talt\taf"

if [[ -f "$COLLAPSED" ]]; then
    # Check if any input VCF is newer than the TSV
    OLDER=0
    for SAMPLE in "${SAMPLES[@]}"; do
        if [[ "${RESULTS}/${SAMPLE}.vcf.gz" -nt "$COLLAPSED" ]]; then
            OLDER=1
            break
        fi
    done
    if [[ $OLDER -eq 0 ]]; then
        exit 0
    fi
fi

TMP_COLLAPSED=$(mktemp)
echo -e "$HEADER" > "$TMP_COLLAPSED"
for SAMPLE in "${SAMPLES[@]}"; do
    bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${RESULTS}/${SAMPLE}.vcf.gz" >> "$TMP_COLLAPSED"
done
mv "$TMP_COLLAPSED" "$COLLAPSED"
exit 0