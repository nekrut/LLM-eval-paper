#!/usr/bin/env bash
set -euo pipefail

# Define sample names
samples=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Paths
RAW_DIR="data/raw"
REF_DIR="data/ref"
RESULTS_DIR="results"

# Create results directory if it doesn't exist
mkdir -p "$RESULTS_DIR"

# Function to check if all expected output files exist
all_outputs_exist() {
    for sample in "${samples[@]}"; do
        bam="$RESULTS_DIR/${sample}.bam"
        bai="${bam}.bai"
        vcf_gz="$RESULTS_DIR/${sample}.vcf.gz"
        tbi="${vcf_gz}.tbi"
        if [[ ! -s "$bam" || ! -s "$bai" || ! -s "$vcf_gz" || ! -s "$tbi" ]]; then
            return 1
        fi
    done
    # Check collapsed.tsv
    if [[ ! -s "$RESULTS_DIR/collapsed.tsv" ]]; then
        return 1
    fi
    return 0
}

# If all outputs already exist, exit successfully
if all_outputs_exist; then
    exit 0
fi

# Ensure reference is indexed for bwa and samtools
REF_FASTA="$REF_DIR/chrM.fa"
BWA_INDEX_PREFIX="${REF_FASTA}.bwt"
SAMTOOLS_FAIDX="${REF_FASTA}.fai"

if [[ ! -s "$BWA_INDEX_PREFIX" ]]; then
    bwa index "$REF_FASTA"
fi

if [[ ! -s "$SAMTOOLS_FAIDX" ]]; then
    samtools faidx "$REF_FASTA"
fi

# Process each sample
for sample in "${samples[@]}"; do
    bam="$RESULTS_DIR/${sample}.bam"
    bai="${bam}.bai"
    vcf_gz="$RESULTS_DIR/${sample}.vcf.gz"
    tbi="${vcf_gz}.tbi"

    # Map reads if BAM not present
    if [[ ! -s "$bam" ]]; then
        bwa mem -t 4 "$REF_FASTA" \
            "$RAW_DIR/${sample}_1.fq.gz" \
            "$RAW_DIR/${sample}_2.fq.gz" | \
        samtools sort -@4 -o "$bam"
        samtools index "$bam"
    fi

    # Call variants if VCF not present
    if [[ ! -s "$vcf_gz" ]]; then
        tmp_vcf="$RESULTS_DIR/${sample}.vcf"
        lofreq call --threads 4 -f "$REF_FASTA" -b "$bam" -o "$tmp_vcf"
        bcftools view -Oz -o "$vcf_gz" "$tmp_vcf"
        rm -f "$tmp_vcf"
        tabix -p vcf "$vcf_gz"
    fi
done

# Create collapsed.tsv if not present
COLLAPSED="$RESULTS_DIR/collapsed.tsv"
if [[ ! -s "$COLLAPSED" ]]; then
    {
        echo -e "sample\tchrom\tpos\tref\talt\taf"
        for sample in "${samples[@]}"; do
            vcf_gz="$RESULTS_DIR/${sample}.vcf.gz"
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t[%INFO/AF]\n' "$vcf_gz" | \
                awk -v s="$sample" '{print s"\t"$0}'
        done
    } > "$COLLAPSED"
fi

exit 0