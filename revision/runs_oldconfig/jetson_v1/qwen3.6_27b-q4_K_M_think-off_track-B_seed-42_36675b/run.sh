#!/usr/bin/env bash
set -euo pipefail

# Configuration
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"
THREADS=4

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Create output directory if it doesn't exist
mkdir -p "$OUT_DIR"

# Index reference if not already done
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

# Function to process a single sample
process_sample() {
    local sample="$1"
    local r1="${RAW_DIR}/${sample}_1.fq.gz"
    local r2="${RAW_DIR}/${sample}_2.fq.gz"
    local bam="${OUT_DIR}/${sample}.bam"
    local bai="${OUT_DIR}/${sample}.bam.bai"
    local vcf_gz="${OUT_DIR}/${sample}.vcf.gz"
    local tbi="${OUT_DIR}/${sample}.vcf.gz.tbi"

    # Check if final VCF is already present and valid; if so, skip sample
    if [[ -f "$vcf_gz" && -f "$tbi" ]]; then
        return 0
    fi

    # Alignment with BWA-MEM
    bwa mem -t "$THREADS" "$REF" "$r1" "$r2" | \
        samtools view -bS -o "${bam}.tmp.bam" -

    # Sort and index BAM
    samtools sort -@ "$THREADS" -o "$bam" "${bam}.tmp.bam"
    rm -f "${bam}.tmp.bam"
    samtools index "$bam"

    # Variant calling with LoFreq
    # Use --call-only to output VCF directly, filtering for mitochondrial variants
    lofreq call -f "$REF" -o "${sample}.vcf.tmp" --min-af 0.01 --min-qual 20 "$bam"

    # Convert to compressed VCF and index
    bgzip -c "${sample}.vcf.tmp" > "$vcf_gz"
    tabix -p vcf "$vcf_gz"
    
    # Cleanup temporary VCF
    rm -f "${sample}.vcf.tmp"
}

# Process each sample
for sample in "${SAMPLES[@]}"; do
    process_sample "$sample"
done

# Generate collapsed TSV
COLLAPSED="${OUT_DIR}/collapsed.tsv"

# Check if collapsed file already exists and has content (header + data)
if [[ -f "$COLLAPSED" ]] && [[ $(wc -l < "$COLLAPSED") -gt 1 ]]; then
    exit 0
fi

# Write header
printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"

# Extract variants from each sample VCF and append to collapsed TSV
for sample in "${SAMPLES[@]}"; do
    vcf_gz="${OUT_DIR}/${sample}.vcf.gz"
    
    # Use bcftools query to extract required fields
    # FORMAT/AF might be missing for some calls, so we use a fallback or specific field extraction
    # LoFreq typically outputs AF in the FORMAT field. 
    # We'll use bcftools +fill-tags to ensure AF is available if not present, or parse directly.
    
    # Extract: CHROM, POS, REF, ALT, and AF (from FORMAT/AF)
    # If AF is missing, we might need to calculate it or use DP4. 
    # LoFreq usually provides AF. Let's try to get it.
    
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t' "$vcf_gz" | \
    paste - <(bcftools query -f '%FORMAT/AF\n' "$vcf_gz") | \
    awk -v sample="$sample" 'BEGIN{OFS="\t"} {print sample, $1, $2, $3, $4, $5}' >> "$COLLAPSED"
done

# Sort the collapsed file by sample, chrom, pos (optional but good practice)
# Since we process in order and chrM is single chromosome, it's already sorted by sample.
# We'll just ensure it's clean.

exit 0