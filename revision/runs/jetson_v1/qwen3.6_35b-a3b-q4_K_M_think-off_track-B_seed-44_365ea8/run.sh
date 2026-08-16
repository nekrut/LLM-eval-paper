#!/usr/bin/env bash
set -euo pipefail

# Configuration
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"
THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Create output directory
mkdir -p "$OUT_DIR"

# Index reference if not present
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

# Function to process a single sample
process_sample() {
    local sample=$1
    local fq1="${RAW_DIR}/${sample}_1.fq.gz"
    local fq2="${RAW_DIR}/${sample}_2.fq.gz"
    local bam="${OUT_DIR}/${sample}.bam"
    local bai="${bam}.bai"
    local vcf_gz="${OUT_DIR}/${sample}.vcf.gz"
    local vcf_tbi="${vcf_gz}.tbi"

    # Skip if all outputs exist (idempotency)
    if [ -f "$bam" ] && [ -f "$bai" ] && [ -f "$vcf_gz" ] && [ -f "$vcf_tbi" ]; then
        return 0
    fi

    # Mapping with BWA-MEM
    # Using -M flag for compatibility with downstream tools like GATK/LoFreq regarding read groups
    bwa mem -t $THREADS -M "$REF" "$fq1" "$fq2" | \
        samtools sort -@ $THREADS -o "$bam" -

    # Index BAM
    samtools index "$bam"

    # Variant Calling with LoFreq
    # LoFreq requires a FASTA reference and a BAM file. It handles base quality recalibration internally.
    lofreq call-parallel \
        -f "$REF" \
        -r "${sample}" \
        -i "$bam" \
        -o "${vcf_gz}.unfiltered.vcf" \
        --no-indels \
        --min-cov 10 \
        --min-freq 0.005

    # Filter variants: keep only those with AF > 0 and standard quality filters if needed.
    # LoFreq output is VCF. We need to ensure it's bgzip compressed and indexed.
    # First, filter for valid sites (remove potential artifacts/low freq noise if necessary, but task asks for variant calling)
    # Let's keep all variants called by lofreq that pass basic filters.
    # Convert unfiltered VCF to bgzip
    bgzip -c "${vcf_gz}.unfiltered.vcf" > "$vcf_gz"
    
    # Index VCF
    tabix -p vcf "$vcf_gz"

    # Clean up intermediate VCF
    rm -f "${vcf_gz}.unfiltered.vcf"
}

# Process all samples in parallel
for sample in "${SAMPLES[@]}"; do
    process_sample "$sample" &
done

wait

# Generate collapsed.tsv
# Header
printf "sample\tchrom\tpos\tref\talt\taf\n" > "${OUT_DIR}/collapsed.tsv"

# Extract variants from each VCF and append to collapsed table
for sample in "${SAMPLES[@]}"; do
    vcf_gz="${OUT_DIR}/${sample}.vcf.gz"
    
    # Use bcftools query to extract specific fields
    # FORMAT: sample chrom pos ref alt AF
    # Note: LoFreq VCF has INFO/AF or FORMAT/GT? Usually INFO/AF for population, but for single sample it might be in INFO.
    # Let's check standard LoFreq output format. It typically puts allele frequency in the INFO field as AF.
    # However, bcftools query can handle this.
    
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_gz" | \
    while IFS=$'\t' read -r chrom pos ref alt af; do
        # Handle multi-allelic sites: bcftools query might output comma-separated AFs if not handled, 
        # but usually for single sample it's one value. If multiple alts, we need to split.
        # LoFreq typically outputs one line per variant site with comma separated ALTs and corresponding AFs.
        
        # Split ALTs and AFs if they are comma-separated
        IFS=',' read -ra alt_arr <<< "$alt"
        IFS=',' read -ra af_arr <<< "$af"
        
        for i in "${!alt_arr[@]}"; do
            local_alt="${alt_arr[$i]}"
            local_af="${af_arr[$i]}"
            
            # Skip if AF is missing or empty
            if [ -z "$local_af" ]; then
                continue
            fi
            
            printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$sample" "$chrom" "$pos" "$ref" "$local_alt" "$local_af"
        done
    done >> "${OUT_DIR}/collapsed.tsv"
done

# Sort the collapsed table by chrom, pos, sample for consistency (optional but good practice)
# The task doesn't specify sort order, but tab-separated with header is required.
# We already wrote the header first. Let's sort the data lines.
head -n 1 "${OUT_DIR}/collapsed.tsv" > "${OUT_DIR}/collapsed_sorted.tsv"
tail -n +2 "${OUT_DIR}/collapsed.tsv" | sort -t$'\t' -k2,2 -k3,3n -k1,1 >> "${OUT_DIR}/collapsed_sorted.tsv"
mv "${OUT_DIR}/collapsed_sorted.tsv" "${OUT_DIR}/collapsed.tsv"