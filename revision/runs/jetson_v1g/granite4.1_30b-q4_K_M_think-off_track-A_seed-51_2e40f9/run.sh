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
if [[ ! -f "$REF.amb" ]]; then
    bwa index "$REF"
fi

# ---- Per-sample processing ------------------------------------------------------
for SAMPLE in "${SAMPLES[@]}"; do
    FASTQ1=data/raw/${SAMPLE}_1.fq.gz
    FASTQ2=data/raw/${SAMPLE}_2.fq.gz
    BAM=$RESULTS/${SAMPLE}.bam
    BAI=$BAM.bai
    VCF=$RESULTS/${SAMPLE}.vcf.gz
    VTBI=$VCF.tbi

    # Skip if final VCF and its index already exist and are newer than inputs
    if [[ -f "$VTBI" && "$VTBI" -nt "$FASTQ1" && "$VTBI" -nt "$FASTQ2" ]]; then
        continue
    fi

    # 3. Alignment with bwa mem (pipe to samtools sort)
    samtools sort -@ "$THREADS" -o "$BAM" \
      <(bwa mem -t "$THREADS" "$REF" "$FASTQ1" "$FASTQ2" \
         -R "@RG\tID:$SAMPLE\tSM:$SAMPLE\tLB:$SAMPLE\tPL:ILLUMINA")

    # 5. Index BAM
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # 6. Variant calling with lofreq call-parallel
    TMP_VCF=$RESULTS/${SAMPLE}.vcf
    if [[ ! -f "$VCF" || "$VCF" -ot "$TMP_VCF" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" --verbose \
            --ref "$REF" --out "$TMP_VCF" "$BAM"
        bgzip -c "$TMP_VCF" > "$VCF"
        rm "$TMP_VCF"
    fi

    # 7. Index VCF if missing
    if [[ ! -f "$VTBI" ]]; then
        tabix -p vcf "$VCF"
    fi
done

# ---- Collapse step ---------------------------------------------------------------
COLLAPSED=$RESULTS/collapsed.tsv
if [[ -f "$COLLAPSED" && "$COLLAPSED" -nt "${SAMPLES[0]}"_1.fq.gz ]]; then
    # All input FASTQs are older than the existing collapsed file → nothing to do
    exit 0
fi

# Rebuild collapsed.tsv
{
    echo -e "sample\tchrom\tpos\tref\talt\taf"
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF=$RESULTS/${SAMPLE}.vcf.gz
        bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF" \
            | sed "s|^|$SAMPLE\t|"
    done
} > "$COLLAPSED"

exit 0