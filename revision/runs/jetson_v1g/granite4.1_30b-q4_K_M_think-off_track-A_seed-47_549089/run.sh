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
    VCF="${RESULTS}/${SAMPLE}.vcf.gz"
    VTBI="${VCF}.tbi"

    # Skip if final VCF and its index already exist and are newer than inputs
    if [[ -f "$VCF" && -f "$VTBI" ]]; then
        INPUTS=(
            data/raw/${SAMPLE}_1.fq.gz
            data/raw/${SAMPLE}_2.fq.gz
            "${REF}.fa"
            "${REF}.amb"
            "${REF}.ann"
            "${REF}.bwt"
            "${REF}.pac"
            "${REF}.sa"
            "${REF}.fai"
        )
        if [[ "$VCF" -nt "${INPUTS[@]}" && "$VTBI" -nt "${INPUTS[@]}" ]]; then
            continue
        fi
    fi

    # 3. Alignment with bwa mem (paired-end)
    bwa mem -t "$THREADS" \
        -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
        "$REF" \
        "data/raw/${SAMPLE}_1.fq.gz" "data/raw/${SAMPLE}_2.fq.gz" |
    # 4. Sort and write BAM
    samtools sort -@ "$THREADS" -o "$BAM"

    # 5. Index BAM
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # 6. Variant calling with lofreq call-parallel
    TMP_VCF="${RESULTS}/${SAMPLE}.vcf"
    if [[ ! -f "$VCF" || "$TMP_VCF" -ot "$BAM" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" --verbose \
            --ref "$REF" --out "$TMP_VCF" \
            "$BAM"
        # 7. Compress and index VCF
        bgzip -c "$TMP_VCF" > "$VCF"
        tabix -p vcf "$VCF"
        rm "$TMP_VCF"
    fi
done

# -------------------------------------------------
# 8. Collapse step → collapsed.tsv (idempotent)
# -------------------------------------------------
COLLAPSED="${RESULTS}/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]] || \
   [[ "$(find "${SAMPLES[@]}" -type f -name '*.vcf.gz' | sort)" -nt "$COLLAPSED" ]]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for SAMPLE in "${SAMPLES[@]}"; do
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
                "${RESULTS}/${SAMPLE}.vcf.gz" | while read -r line; do
                echo -e "${SAMPLE}\t$line"
            done
        done
    } > "$COLLAPSED"
fi

# Script ends successfully (no extra output)