#!/usr/bin/env bash
set -euo pipefail

REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"
THREADS="${THREADS:-4}"

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p "$OUT_DIR"

[[ -f "${REF}.bwt" ]] || bwa index "$REF"
[[ -f "${REF}.fai" ]] || samtools faidx "$REF"

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="${OUT_DIR}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF="${OUT_DIR}/${SAMPLE}.vcf.gz"
    TBI="${VCF}.tbi"

    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" "$REF" "$R1" "$R2" | \
            samtools sort -@ "$THREADS" -o "$BAM"
    fi

    if [[ ! -f "$BAI" ]]; then
        samtools index "$BAM"
    fi

    if [[ ! -f "$VCF" ]]; then
        bcftools mpileup -f "$REF" -Ou "$BAM" | \
            bcftools call -mv -Oz -o "$VCF"
    fi

    if [[ ! -f "$TBI" ]]; then
        tabix -p vcf "$VCF"
    fi
done

if [[ ! -f "${OUT_DIR}/collapsed.tsv" ]]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "${OUT_DIR}/collapsed.tsv"

    for SAMPLE in "${SAMPLES[@]}"; do
        VCF="${OUT_DIR}/${SAMPLE}.vcf.gz"
        bcftools query -f "%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF" | \
            awk -F'\t' -v sample="$SAMPLE" '{
                n = split($4, alts, ",");
                m = split($5, afs, ",");
                for (i=1; i<=n; i++) {
                    af = "NA";
                    if (i <= m && afs[i] != "" && afs[i] != ".") {
                        af = afs[i];
                    }
                    print sample"\t"$1"\t"$2"\t"$3"\t"alts[i]"\t"af
                }
            }' >> "${OUT_DIR}/collapsed.tsv"
    done
fi