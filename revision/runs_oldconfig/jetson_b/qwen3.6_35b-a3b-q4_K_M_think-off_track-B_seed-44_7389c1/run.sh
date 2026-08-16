#!/usr/bin/env bash
set -euo pipefail

# Configuration
THREADS=4
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"

# Create output directory
mkdir -p "$OUT_DIR"

# Index reference if not present
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

# Define samples and their read pairs
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

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

    # Step 1: Alignment with BWA-MEM
    # Use -M for marking shorter split hits as secondary (compatible with GATK/bcftools)
    bwa mem -t $THREADS -M "$REF" "$fq1" "$fq2" | \
        samtools view -b -@ $THREADS -o "$bam" -

    # Step 2: Sort and Index BAM
    if [ ! -f "$bai" ]; then
        samtools sort -@ $THREADS -o "${bam}.sorted.bam" "$bam"
        mv "${bam}.sorted.bam" "$bam"
        samtools index -@ $THREADS "$bam"
    fi

    # Step 3: Variant Calling with LoFreq
    # LoFreq requires a FASTA reference and a BAM file.
    # It performs base quality recalibration internally based on the alignment.
    if [ ! -f "$vcf_gz" ]; then
        lofreq call-parallel \
            -f "$REF" \
            -r "${bam}.bai" \
            -i "$bam" \
            -o "$vcf_gz" \
            --nproc $THREADS \
            --min-cov 10 \
            --min-freq 0.005
        
        # Index VCF
        tabix -p vcf "$vcf_gz"
    fi
}

# Process all samples in parallel
for sample in "${SAMPLES[@]}"; do
    process_sample "$sample" &
done

wait

# Step 4: Collapse VCFs into a single TSV
# We need to extract: sample, chrom, pos, ref, alt, af (INFO/AF or FORMAT/AF)
# LoFreq outputs AF in the INFO field as 'AF'.
# Format: sample\tchrom\tpos\tref\talt\taf

collapsed_file="${OUT_DIR}/collapsed.tsv"

# Write header
printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed_file"

for sample in "${SAMPLES[@]}"; do
    vcf_gz="${OUT_DIR}/${sample}.vcf.gz"
    
    # Check if VCF exists and has variants (skip empty files gracefully)
    if [ ! -s "$vcf_gz" ]; then
        continue
    fi

    # Use bcftools to extract fields
    # --no-header: don't print header
    # --output-type t: tab-separated output
    # --fields: sample,CHROM,POS,REF,ALT,INFO/AF
    bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_gz" | \
        while IFS=$'\t' read -r s chrom pos ref alt af; do
            # Handle multi-allelic sites: bcftools query might output comma-separated values for ALT or AF
            # We need to split them into separate rows if necessary.
            # However, standard LoFreq usually outputs biallelic SNPs/Indels per line.
            # If AF is a list (e.g., "0.5,0.1"), we should split it.
            
            # Split ALT and AF if they contain commas
            IFS=',' read -ra alts <<< "$alt"
            IFS=',' read -ra afs <<< "$af"
            
            # Ensure lengths match (they should)
            len=${#alts[@]}
            for (( i=0; i<len; i++ )); do
                a="${alts[$i]}"
                f="${afs[$i]}"
                printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$s" "$chrom" "$pos" "$ref" "$a" "$f"
            done
        done >> "$collapsed_file"
done

# Clean up intermediate files if desired, but keeping BAM is often useful.
# The task requires specific outputs, so we leave them.