#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RESULTS=results

mkdir -p "$RESULTS"

# -------------------------------------------------
# 2. Reference indexing (once, idempotent)
# -------------------------------------------------
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi
if [[ ! -f "${REF}.amb" ]]; then
    bwa index "$REF"
fi

# -------------------------------------------------
# 3‑7. Per-sample processing (idempotent)
# -------------------------------------------------
for SAMPLE in "${SAMPLES[@]}"; do
    BAM="${RESULTS}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${RESULTS}/${SAMPLE}.vcf.gz"
    VCF_TBI="${VCF_GZ}.tbi"

    # Skip if final compressed VCF already exists and is newer than inputs
    if [[ -f "$VCF_GZ" && -f "$VCF_TBI" ]]; then
        INPUTS=(
            data/raw/"${SAMPLE}"_1.fq.gz
            data/raw/"${SAMPLE}"_2.fq.gz
            "${REF}"
            "${REF}.amb"
            "${REF}.ann"
            "${REF}.bwt"
            "${REF}.pac"
            "${REF}.sa"
            "${REF}.fa.fai"
        )
        if [[ "$VCF_GZ" -nt "${INPUTS[@]}" && "$VCF_TBI" -nt "${INPUTS[@]}" ]]; then
            continue
        fi
    fi

    # 3. Alignment with bwa mem (paired-end)
    bwa mem -t "$THREADS" \
        -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
        "$REF" \
        data/raw/"${SAMPLE}"_1.fq.gz \
        data/raw/"${SAMPLE}"_2.fq.gz |
    # 4. Sort and write BAM
    samtools sort -@ "$THREADS" -o "$BAM"

    # 5. Index BAM
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # 6. Variant calling with lofreq call-parallel
    lofreq call-parallel --pp-threads "$THREADS" --verbose \
        --ref "$REF" --out "${RESULTS}/${SAMPLE}.vcf" \
        "$BAM"

    # 7. Compress and index VCF, then clean up uncompressed version
    if [[ ! -f "$VCF_GZ" || ! -f "$VCF_TBI" ]]; then
        bgzip -c "${RESULTS}/${SAMPLE}.vcf" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm -f "${RESULTS}/${SAMPLE}.vcf"
    fi
done

# -------------------------------------------------
# 8. Collapse step → collapsed.tsv (idempotent)
# -------------------------------------------------
COLLAPSED="${RESULTS}/collapsed.tsv"
if [[ -f "$COLLAPSED" ]]; then
    INPUTS_VCF=()
    for SAMPLE in "${SAMPLES[@]}"; do
        INPUTS_VCF+=("${RESULTS}/${SAMPLE}.vcf.gz")
    done
    if [[ "$COLLAPSED" -nt "${INPUTS_VCF[@]}" ]]; then
        # Already up‑to‑date, exit early
        exit 0
    fi
fi

# Rebuild collapsed table
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for SAMPLE in "${SAMPLES[@]}"; do
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            "${RESULTS}/${SAMPLE}.vcf.gz" |
        while IFS=$'\t' read -r chrom pos ref alt af; do
            echo -e "${SAMPLE}\t${chrom}\t${pos}\t${ref}\t${alt}\t${af}"
        done
    done
} > "$COLLAPSED"

# -------------------------------------------------
# Script ends (exits 0)
# -------------------------------------------------
exit 0