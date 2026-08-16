#!/usr/bin/env bash
set -euo pipefail

THREADS="${THREADS:-4}"
REF="data/ref/chrM.fa"
RAW="data/raw"
OUT="results"

mkdir -p "$OUT"

# --- Index reference (idempotent) ---
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

for s in "${samples[@]}"; do
    R1="${RAW}/${s}_1.fq.gz"
    R2="${RAW}/${s}_2.fq.gz"
    BAM="${OUT}/${s}.bam"
    BAI="${OUT}/${s}.bam.bai"
    VCF="${OUT}/${s}.vcf.gz"
    TBI="${OUT}/${s}.vcf.gz.tbi"

    if [[ -s "$BAM" && -s "$BAI" ]]; then
        :
    else
        bwa mem -t "$THREADS" "$REF" "$R1" "$R2" \
            | samtools sort -@ "$THREADS" -o "${BAM}.tmp" -
        mv "${BAM}.tmp" "$BAM"
        samtools index -@ "$THREADS" "$BAM"
    fi

    if [[ -s "$VCF" && -s "$TBI" ]]; then
        :
    else
        RAW_VCF="${OUT}/${s}.raw.vcf"
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$RAW_VCF" "$BAM"
        bgzip -f "$RAW_VCF"
        mv -f "${RAW_VCF}.gz" "$VCF"
        tabix -f -p vcf "$VCF"
    fi
done

TMP_TSV="${OUT}/collapsed.tsv.tmp"
{
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for s in "${samples[@]}"; do
        VCF="${OUT}/${s}.vcf.gz"
        bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF"
    done
} > "$TMP_TSV"
mv -f "$TMP_TSV" "${OUT}/collapsed.tsv"