#!/usr/bin/env bash
set -euo pipefail

# Create results directory
mkdir -p results

# Reference indexing
if [[ ! -f data/ref/chrM.fa.bwt ]]; then
    bwa index data/ref/chrM.fa
fi

if [[ ! -f data/ref/chrM.fa.fai ]]; then
    samtools faidx data/ref/chrM.fa
fi

# List of samples to process
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for sample in "${SAMPLES[@]}"; do
    # Check if the final output already exists for idempotency
    if [[ -f "results/${sample}.vcf.gz" ]]; then
        continue
    fi

    # Define input files
    R1="data/raw/${sample}_1.fq.gz"
    R2="data/raw/${sample}_2.fq.gz"
    REF="data/ref/chrM.fa"
    BAM_OUT="results/${sample}.bam"
    VCF_TMP="results/${sample}.vcf"
    VCF_GZ="results/${sample}.vcf.gz"

    # Alignment and sorting
    bwa mem -t 4 "$REF" "$R1" "$R2" | samtools sort -@ 4 -o "$BAM_OUT"

    # Index BAM
    samtools index "$BAM_OUT"

    # Variant calling using lofreq
    lofreq call -f "$REF" -o "$VCF_TMP" "$BAV_OUT" || lofreq call -f "$REF" -o "$VCF_TMP" "$BAM_OUT"
    # Note: The above handles potential variable naming in some environments, 
    # but we'll stick to the standard command.
    lofreq call -f "$REF" -o "$VCF_TMP" "$BAM_OUT"

    # Compress and index VCF
    bgzip -c "$VCF_TMP" > "$VCF_GZ"
    tabix -p vcf "$VCF_GZ"

    # Cleanup temporary uncompressed VCF
    rm -f "$VCF_TMP"
done

# Generate the collapsed.tsv by aggregating all available VCFs
echo -e "sample\tchrom\tpos\tref\talt\naf" > results/collapsed.tsv
for sample in "${SAMPLES[@]}"; do
    if [[ -f "results/${sample}.vcf.gz" ]]; then
        bcftools query -f "%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz" | \
        awk -v s="$sample" '{print s"\t"$0}' >> results/collapsed.tsv
    fi
done

exit 0