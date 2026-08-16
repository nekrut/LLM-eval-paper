#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

REF="data/ref/chrM.fa"
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="results/${SAMPLE}.bam"
    VCF_GZ="results/${SAMPLE}.vcf.gz"
    R1="data/raw/${SAMPLE}_1.fq.gz"
    R2="data/raw/${SAMPLE}_2.fq.gz"

    if [[ ! -f "$BAM" ]]; then
        bwa mem -t 4 "$REF" "$R1" "$R2" | samtools sort -@ 4 -o "$BAM" -
        samtools index "$BAM"
    fi

    if [[ ! -f "$VCF_GZ" ]]; then
        TEMP_VCF="results/${SAMPLE}.vcf"
        # lofreq call is used for high-sensitivity mitochondrial variant calling
        if lofreq call -f "$REF" -o "$TEMP_VCF" "$BAM"; then
            bcftools view -Oz -o "$VCF_GZ" "$TEMP_VCF"
            rm "$TEMP_VCF"
            tabix -p vcf "$VCF_GZ"
        fi
    fi
done

COLLAPSED="results/collapsed.tsv"
echo -e "sample\tchrom\tpos\tref\talt\taf" > "$COLLAPSED"

for SAMPLE in "${SAMPLES[@]}"; do
    VCF_GZ="results/${SAMPLE}.vcf.gz"
    if [[ -f "$VCF_GZ" ]]; then
        # Extracting variant info and ensuring 6-column structure for the collapsed table
        bcftools query -f "%CHROM\t%POS\t%REF\t%ALT[\t%AF]\n" "$VCF_GZ" | \
        awk -v s="$SAMPLE" 'BEGIN{OFS="\t"} {if(NF<5) print s, $1, $2, $3, $4, "0"; else print s, $1, $2, $3, $4, $5}' >> "$COLLAPSED"
    fi
done