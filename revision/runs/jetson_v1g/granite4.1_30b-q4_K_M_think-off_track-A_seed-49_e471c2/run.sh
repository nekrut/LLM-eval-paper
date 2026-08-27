#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RESULTS=results

mkdir -p "$RESULTS"

# ---- Reference indexing (once) -------------------------------------------------
if [[ ! -f "$REF.fai" ]]; then
    samtools faidx "$REF"
fi
if [[ ! -f "$REF.bwt" ]]; then
    bwa index "$REF"
fi

# ---- Per-sample processing ------------------------------------------------------
for SAMPLE in "${SAMPLES[@]}"; do
    FASTQ1=data/raw/"${SAMPLE}"_1.fq.gz
    FASTQ2=data/raw/"${SAMPLE}"_2.fq.gz
    BAM="$RESULTS/${SAMPLE}.bam"
    BAI="$BAM.bai"
    VCF="$RESULTS/${SAMPLE}.vcf.gz"
    VTBI="$VCF.tbi"

    # Skip if final VCF and its index already exist and are newer than inputs
    if [[ -f "$VTBI" && "$VTBI" -nt "$FASTQ1" && "$VTBI" -nt "$FASTQ2" ]]; then
        continue
    fi

    # 3. Alignment with bwa mem (pipe directly to samtools sort)
    bwa mem -t "$THREADS" \
        -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
        "$REF" "$FASTQ1" "$FASTQ2" |
    samtools sort -@ "$THREADS" -o "$BAM"

    # 5. Index BAM
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # 6. Variant calling with lofreq call-parallel
    TMP_VCF="${BAM}.vcf"
    if [[ ! -f "$VCF" || "$TMP_VCF" -ot "$BAI" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" --verbose \
            --ref "$REF" --out "$TMP_VCF" "$BAM"
        # Compress and index VCF
        bgzip -c "$TMP_VCF" > "$VCF"
        tabix -p vcf "$VCF"
        rm "$TMP_VCF"
    fi
done

# ---- Collapse step ---------------------------------------------------------------
COLLAPSED="$RESULTS/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]] || \
   [[ "$(find "${SAMPLES[@]}" -type f -name '*.vcf.gz' -newer "$COLLAPSED")" ]]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for SAMPLE in "${SAMPLES[@]}"; do
            VCF="$RESULTS/${SAMPLE}.vcf.gz"
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF" |
                awk -v sample="$SAMPLE" '{print sample "\t" $0}'
        done
    } > "$COLLAPSED"
fi

# Script exits 0 when all steps complete (idempotent re‑run does nothing)