#!/usr/bin/env bash
set -euo pipefail

# Create output directory
mkdir -p results

# Reference files
REF=data/ref/chrM.fa
REF_BWT="${REF}.bwt"
REF_PAC="${REF}.pac"
REF_ANI="${REF}.ann"
REF_AMB="${REF}.amb"
REF_SA="${REF}.sa"

# Index reference if not present (idempotent)
if [ ! -f "$REF_BWT" ]; then
    bwa index "$REF"
fi

# Define samples and their read pairs
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for SAMPLE in "${SAMPLES[@]}"; do
    R1="data/raw/${SAMPLE}_1.fq.gz"
    R2="data/raw/${SAMPLE}_2.fq.gz"
    BAM="results/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="results/${SAMPLE}.vcf.gz"
    VCF_TBI="${VCF_GZ}.tbi"

    # Step 1: Alignment with bwa mem
    if [ ! -s "$BAM" ]; then
        bwa mem -t 4 "$REF" "$R1" "$R2" | samtools view -bS - > "$BAM"
    fi

    # Step 2: Sort and index BAM
    SORTED_BAM="results/${SAMPLE}.sorted.bam"
    if [ ! -s "$SORTED_BAM" ]; then
        samtools sort -t 4 -o "$SORTED_BAM" "$BAM"
    fi
    
    if [ ! -s "$BAI" ]; then
        samtools index "$SORTED_BAM" "${SORTED_BAM}.bai"
        # Rename to expected output name for consistency, or just use sorted BAM as the final BAM
        # The task asks for results/{sample}.bam and .bai. Let's move/copy sorted BAM to that name if not exists
        if [ ! -s "$BAM" ] || [ "$BAM" != "$SORTED_BAM" ]; then
             mv "$SORTED_BAM" "$BAM"
             mv "${SORTED_BAM}.bai" "$BAI"
        fi
    fi

    # Step 3: Variant calling with lofreq
    if [ ! -s "$VCF_GZ" ]; then
        # LoFreq requires a reference index (fai) for the target region usually, 
        # but since we mapped to chrM, we can use the ref directly.
        # First ensure fai exists
        if [ ! -f "${REF}.fai" ]; then
            samtools faidx "$REF"
        fi
        
        lofreq call-parallel \
            -f "$REF" \
            -r "chrM:1-16569" \
            -i "$BAM" \
            -o "${SAMPLE}_raw.vcf" \
            --no-indel-realign \
            --no-qc-filter \
            -t 4
        
        # Compress and index VCF
        bgzip -f "${SAMPLE}_raw.vcf"
        tabix -p vcf "${SAMPLE}_raw.vcf.gz"
        
        mv "${SAMPLE}_raw.vcf.gz" "$VCF_GZ"
        mv "${SAMPLE}_raw.vcf.gz.tbi" "$VCF_TBI"
    fi
done

# Step 4: Collapse VCFs into a single TSV
# Columns: sample chrom pos ref alt af
COLLAPSED="results/collapsed.tsv"

# Write header
printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"

for SAMPLE in "${SAMPLES[@]}"; do
    VCF_GZ="results/${SAMPLE}.vcf.gz"
    
    # Use bcftools query to extract fields efficiently
    # Format: sample, chrom, pos, ref, alt, AF (from INFO/AF or FORMAT/GT if needed, but lofreq outputs AF in INFO)
    # LoFreq VCF format typically has AF in the INFO field.
    # We need to handle multi-allelic sites by exploding them if necessary, 
    # but bcftools query can handle comma-separated alts/afs if we split them or just take the first.
    # Standard practice for "collapsed" often implies one row per variant site per sample.
    # However, if a site has multiple alt alleles, they are usually separate rows in standard VCF processing 
    # or comma-separated in INFO. The prompt asks for 'alt' and 'af'. 
    # Let's assume we want one row per alternate allele to be precise, or just the primary call.
    # Given "collapsed.tsv" usually implies a simple table, let's extract each ALT allele as a separate row if multi-allelic,
    # or just use bcftools +split-vep or similar. 
    # Simpler approach: Use bcftools query to get all fields, then awk to split commas in ALT/AF columns.
    
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF_GZ" | \
    while IFS=$'\t' read -r chrom pos ref alt af; do
        # Skip if no AF or empty
        [ -z "$af" ] && continue
        
        # Handle multi-allelic sites: ALT and AF are comma-separated lists corresponding to each other
        # Split by comma
        IFS=',' read -ra alts <<< "$alt"
        IFS=',' read -ra afs <<< "$af"
        
        for i in "${!alts[@]}"; do
            a="${alts[$i]}"
            f="${afs[$i]}"
            # Skip if alt is missing or empty (shouldn't happen but safe)
            [ -z "$a" ] && continue
            printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$SAMPLE" "$chrom" "$pos" "$ref" "$a" "$f"
        done
    done >> "$COLLAPSED"
done