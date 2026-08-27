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
    VCF="${RESULTS}/${SAMPLE}.vcf.gz"
    VTBI="${VCF}.tbi"

    # Skip if final compressed VCF already exists and is newer than inputs
    if [[ -f "$VCF" && -z $(find data/raw/"${SAMPLE}"*_1.fq.gz data/raw/"${SAMPLE}"*_2.fq.gz -newer "$VCF") ]]; then
        continue
    fi

    # 3. Alignment with bwa mem (pipe directly to samtools sort)
    samtools sort -@ "$THREADS" -o "$BAM" \
      <(bwa mem -t "$THREADS" \
          -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
          "$REF" \
          "data/raw/${SAMPLE}_1.fq.gz" "data/raw/${SAMPLE}_2.fq.gz")

    # 5. Index BAM if missing or older than the BAM
    if [[ ! -f "$BAI" || "$BAI" -ot "$BAM" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # 6‑7. Variant calling with lofreq, compress & index VCF
    UNCOMP_VCF="${RESULTS}/${SAMPLE}.vcf"
    if [[ ! -f "$VCF" || "$VCF" -ot "$UNCOMP_VCF" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$UNCOMP_VCF" "$BAM"
        bgzip -c "$UNCOMP_VCF" > "$VCF"
        tabix -p vcf "$VCF"
        rm -f "$UNCOMP_VCF"
    fi
done

# -------------------------------------------------
# 8. Collapse step → collapsed.tsv (idempotent)
# -------------------------------------------------
COLLAPSED="${RESULTS}/collapsed.tsv"
if [[ ! -f "$COLLAPSED" || "$(find "${RESULTS}"/*.vcf.gz) "newer than $COLLAPSED ]]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for SAMPLE in "${SAMPLES[@]}"; do
            VCF="${RESULTS}/${SAMPLE}.vcf.gz"
            bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF" | sed "s|^|${SAMPLE}\t|"
        done
    } > "$COLLAPSED"
fi

# Script ends; on a fully populated results/ directory it exits 0 with no work performed.