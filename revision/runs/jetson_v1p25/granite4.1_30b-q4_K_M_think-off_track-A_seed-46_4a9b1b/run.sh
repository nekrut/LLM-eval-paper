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
# 3‑7. Per‑sample processing (idempotent)
# -------------------------------------------------
for SAMPLE in "${SAMPLES[@]}"; do
    BAM="${RESULTS}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF_UNCOMPRESSED="${RESULTS}/${SAMPLE}.vcf"
    VCF_GZ="${VCF_UNCOMPRESSED}.gz"
    VCF_TBI="${VCF_GZ}.tbi"

    # Skip if final compressed + indexed VCF already exists and is newer than inputs
    if [[ -f "$VCF_TBI" && "$VCF_TBI" -nt "${REF}" && "$VCF_TBI" -nt "data/raw/${SAMPLE}_1.fq.gz" && "$VCF_TBI" -nt "data/raw/${SAMPLE}_2.fq.gz" ]]; then
        continue
    fi

    # 3. Alignment with bwa mem (paired‑end)
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

    # 6. Variant calling with lofreq (uncompressed VCF)
    if [[ ! -f "$VCF_UNCOMPRESSED" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF_UNCOMPRESSED" "$BAM"
    fi

    # 7. Compress and index VCF, remove uncompressed version
    if [[ ! -f "$VCF_GZ" || ! -f "$VCF_TBI" ]]; then
        bgzip -c "$VCF_UNCOMPRESSED" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "$VCF_UNCOMPRESSED"
    fi
done

# -------------------------------------------------
# 8. Collapse step → collapsed.tsv (idempotent)
# -------------------------------------------------
COLLAPSED="${RESULTS}/collapsed.tsv"
if [[ -f "$COLLAPSED" && "$COLLAPSED" -nt "${REF}" ]]; then
    for SAMPLE in "${SAMPLES[@]}"; do
        if [[ "$COLLAPSED" -ot "${RESULTS}/${SAMPLE}.vcf.gz" ]]; then
            : # need to rebuild because an input VCF changed
            break
        fi
    done
    # If the loop completed without a break, all inputs are older or same age → no rebuild needed
    if [[ ${PIPESTATUS[0]} -eq 0 && -z "${REBUILD+x}" ]]; then
        exit 0
    fi
fi

# Rebuild collapsed.tsv
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for SAMPLE in "${SAMPLES[@]}"; do
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${RESULTS}/${SAMPLE}.vcf.gz" | while read -r chrom pos ref alt af; do
            echo -e "${SAMPLE}\t${chrom}\t${pos}\t${ref}\t${alt}\t${af}"
        done
    done
} > "$COLLAPSED"

# -------------------------------------------------
# Script ends (exits 0)
# -------------------------------------------------