#!/usr/bin/env bash
set -euo pipefail

# Configuration
THREADS=4
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"

# Create output directory if it doesn't exist
mkdir -p "$OUT_DIR"

# Index reference if not already present
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi
if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi

# Define samples and their read files
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Function to check if a file exists and is up-to-date relative to inputs
# For simplicity in this script, we check existence of key output files.
# Since the task requires idempotency, we skip processing if outputs exist.

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="${OUT_DIR}/${SAMPLE}.bam"
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
    
    # Skip if final VCF already exists (implies BAM and intermediate steps are done)
    if [ -f "$VCF_GZ" ]; then
        continue
    fi

    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    # 1. Alignment with BWA-MEM
    # Use samtools view to convert SAM to BAM and sort simultaneously to save disk I/O
    if [ ! -f "$BAM" ]; then
        bwa mem -t "$THREADS" "$REF" "$R1" "$R2" | \
            samtools sort -@ "$THREADS" -o "$BAM" -
        
        # 2. Index BAM
        samtools index "$BAM"
    fi

    # 3. Variant Calling with LoFreq
    # LoFreq requires a FASTA reference and a sorted BAM. It generates a VCF.
    if [ ! -f "$VCF_GZ" ]; then
        lofreq call-parallel \
            -f "$REF" \
            -i "$BAM" \
            -o "${OUT_DIR}/${SAMPLE}.vcf" \
            --nproc "$THREADS" \
            --no-indels 2>/dev/null || true
        
        # Compress and index VCF
        bcftools view -O z -o "$VCF_GZ" "${OUT_DIR}/${SAMPLE}.vcf"
        tabix -p vcf "$VCF_GZ"
        
        # Clean up uncompressed VCF
        rm -f "${OUT_DIR}/${SAMPLE}.vcf"
    fi
done

# 4. Collapse all VCFs into a single TSV
COLLAPSED="${OUT_DIR}/collapsed.tsv"

# Check if collapsed file exists and is non-empty
if [ ! -s "$COLLAPSED" ]; then
    # Write header
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
        
        if [ -f "$VCF_GZ" ]; then
            # Use bcftools query to extract fields: CHROM, POS, REF, ALT, INFO/AF (or FORMAT/GT based AF)
            # LoFreq typically puts allele frequency in the INFO field as AF or in the FORMAT.
            # Standard VCF format for LoFreq often uses INFO/AF for global AF or per-sample AF if multi-sample.
            # Here we have single sample VCFs. The AF is usually in the INFO column or GT:GQ:DP:AF.
            # Let's try to extract AF from the last column of the FORMAT field if present, or INFO/AF.
            # LoFreq 2.1.5 output format: 
            # CHROM POS ID REF ALT QUAL FILTER INFO FORMAT SAMPLE
            # Often AF is in INFO. Let's use bcftools query to get it robustly.
            
            # Extract fields: sample_name, chrom, pos, ref, alt, af
            # Note: LoFreq might output multiple alleles. We need to handle them.
            # The format string '%s\t%v\t%T\t%r\t%a\n' corresponds to:
            # %s = Sample name (from --samples-list or just the sample column)
            # %v = Allele frequency (if available in FORMAT/AF)
            # %T = Genotype
            # %r = Reference allele
            # %a = Alternate allele
            
            # However, simpler approach for collapsed table:
            # Use bcftools query to pull CHROM, POS, REF, ALT, and AF.
            # LoFreq VCFs often have AF in the INFO field.
            
            bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF_GZ" 2>/dev/null | \
            while IFS=$'\t' read -r chrom pos ref alt af; do
                # Handle missing AF (sometimes empty)
                if [ -z "$af" ]; then
                    af="."
                fi
                # LoFreq might output comma-separated alts/afs. We need to explode them.
                # Split by comma and print one line per allele
                IFS=',' read -ra ALT_ARR <<< "$alt"
                IFS=',' read -ra AF_ARR <<< "$af"
                
                for i in "${!ALT_ARR[@]}"; do
                    alt_val="${ALT_ARR[$i]}"
                    af_val="${AF_ARR[$i]:-}"
                    if [ -z "$af_val" ]; then
                        af_val="."
                    fi
                    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$SAMPLE" "$chrom" "$pos" "$ref" "$alt_val" "$af_val"
                done
            done >> "$COLLAPSED"
        fi
    done
    
    # Sort the collapsed file by chrom and pos for consistency (optional but good practice)
    # Header is line 1, rest is data.
    head -n 1 "$COLLAPSED" > "${COLLAPSED}.tmp"
    tail -n +2 "$COLLAPSED" | sort -t$'\t' -k2,2 -k3,3n >> "${COLLAPSED}.tmp"
    mv "${COLLAPSED}.tmp" "$COLLAPSED"
fi