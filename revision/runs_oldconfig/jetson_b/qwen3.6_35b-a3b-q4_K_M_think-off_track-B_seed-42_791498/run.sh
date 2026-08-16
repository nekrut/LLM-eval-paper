#!/usr/bin/env bash
set -euo pipefail

# Configuration
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"
THREADS=4

# Create output directory
mkdir -p "$OUT_DIR"

# Index reference if not present
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi
if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi

# Define samples and their read files
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Function to process a single sample
process_sample() {
    local sample=$1
    local r1="${RAW_DIR}/${sample}_1.fq.gz"
    local r2="${RAW_DIR}/${sample}_2.fq.gz"
    
    # Check if input files exist
    if [ ! -f "$r1" ] || [ ! -f "$r2" ]; then
        return 0
    fi

    # Output paths
    local bam="${OUT_DIR}/${sample}.bam"
    local bai="${bam}.bai"
    local vcf_gz="${OUT_DIR}/${sample}.vcf.gz"
    local vcf_tbi="${vcf_gz}.tbi"
    
    # Skip if all outputs exist (idempotency)
    if [ -f "$bam" ] && [ -f "$bai" ] && [ -f "$vcf_gz" ] && [ -f "$vcf_tbi" ]; then
        return 0
    fi

    # Step 1: Alignment
    bwa mem -t "$THREADS" "$REF" "$r1" "$r2" | \
        samtools view -b -o "$bam" -@ "$THREADS" -
    
    # Step 2: Sort and Index BAM
    if [ ! -f "${bam}.sorted.bam" ]; then
        samtools sort -o "${bam}.sorted.bam" -@ "$THREADS" "$bam"
        rm "$bam"
        mv "${bam}.sorted.bam" "$bam"
    fi
    
    if [ ! -f "$bai" ]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    # Step 3: Variant Calling with LoFreq
    # LoFreq requires a FASTA reference and a BAM file.
    # It generates a VCF directly.
    if [ ! -f "$vcf_gz" ]; then
        lofreq call-parallel \
            --ref-fa "$REF" \
            -f "$REF" \
            -i "$bam" \
            -o "${OUT_DIR}/${sample}_raw.vcf" \
            --nproc "$THREADS" \
            --min-cov 10 \
            --min-freq 0.005
        
        # Compress and index VCF
        bgzip -c "${OUT_DIR}/${sample}_raw.vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        
        # Clean up intermediate VCF
        rm "${OUT_DIR}/${sample}_raw.vcf"
    fi
}

# Process all samples
for sample in "${SAMPLES[@]}"; do
    process_sample "$sample"
done

# Step 4: Collapse VCFs into a single TSV
COLLAPSED="${OUT_DIR}/collapsed.tsv"

# Write header
printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"

# Iterate over samples again to extract variants
for sample in "${SAMPLES[@]}"; do
    local_vcf="${OUT_DIR}/${sample}.vcf.gz"
    
    if [ ! -f "$local_vcf" ]; then
        continue
    fi
    
    # Extract fields: CHROM, POS, REF, ALT, INFO/AF (or FORMAT/GT based on VCF structure)
    # LoFreq VCF format typically has AF in the INFO field or as a separate column depending on version.
    # Standard bcftools query is robust for extracting specific tags.
    # For LoFreq 2.1.5, the allele frequency is often in the INFO field as 'AF' or 'MQ0'.
    # Let's use bcftools to extract CHROM, POS, REF, ALT, and AF from INFO.
    
    bcftools query -f "%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$local_vcf" | \
        while IFS=$'\t' read -r chrom pos ref alt af; do
            # Handle multi-allelic sites where AF might be comma-separated or missing
            if [ -z "$af" ]; then
                continue
            fi
            
            # If multiple alleles, AF is comma separated. We need to explode them.
            # Split by comma and output one line per alt allele
            IFS=',' read -ra af_array <<< "$af"
            IFS=',' read -ra alt_array <<< "$alt"
            
            for i in "${!alt_array[@]}"; do
                local_alt="${alt_array[$i]}"
                local_af="${af_array[$i]}"
                
                # If AF array is shorter than ALT array (shouldn't happen normally but safe check)
                if [ -z "$local_af" ]; then
                    continue
                fi
                
                printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$sample" "$chrom" "$pos" "$ref" "$local_alt" "$local_af"
            done
        done >> "$COLLAPSED"
done

# Ensure the collapsed file is sorted by sample, chrom, pos for consistency (optional but good practice)
# The header must remain at the top.
head -1 "$COLLAPSED" > "${COLLAPSED}.tmp"
tail -n +2 "$COLLAPSED" | sort -t$'\t' -k1,1 -k2,2V -k3,3n >> "${COLLAPSED}.tmp"
mv "${COLLAPSED}.tmp" "$COLLAPSED"