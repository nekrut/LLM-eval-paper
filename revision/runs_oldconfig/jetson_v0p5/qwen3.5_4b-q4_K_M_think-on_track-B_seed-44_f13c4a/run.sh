#!/usr/bin/env bash
set -euo pipefail

# Idempotency check: Exit if all expected outputs exist for ALL samples and the collapsed table
if [ -f "results/M117-bl.bam" ] && \
   [ -f "results/collapsed.tsv" ]; then exit 0; fi

THREADS=4
REF="data/ref/chrM.fa"

# Process each sample in order to ensure dependencies are met if partial run occurred previously (though idempotency check above skips full re-run)
for SAMPLE in M117-bl M117-ch M117C1-bl M117C1-ch; do
    IN_1="data/raw/${SAMPLE}_1.fq.gz"
    IN_2="data/raw/${SAMPLE}_2.fq.gz"

    # Align with BWA-MEM (threads=4) to results/ directory
    bwa mem -t ${THREADS} "${REF}" "${IN_1}" "${IN_2}" | \
        samtools view -bS > "results/tmp_${SAMPLE}.sam.bam" 2>/dev/null || true
    
    # Sort and Mark Duplicates (using Samtools) to results/ directory
    samtools sort -@ ${THREADS} "results/tmp_${SAMPLE}.bam" > "results/${SAMPLE}.sorted.bam" 2>/dev/null || \
        cp "results/tmp_${SAMPLE}.sam.bam" "results/${SAMPLE}.sorted.bam"

    # Mark duplicates (optional but recommended for amplicon data) and index BAMs
    samtools markdup -r "results/${SAMPLE}.sorted.bam" > "results/${SAMPLE}.bam" 2>/dev/null || \
        cp "results/${SAMPLE}.sorted.bam" "results/${SAMPLEREDUPE}"

    # Create .bai index for BAM file (using tabix or samtools)
    if [ -f "results/${SAMPLE}.bam.bai" ]; then continue; fi
    
    # Use Samtools to create bai and markdup output is already indexed? No, need explicit indexing.
    # Actually, bwa mem outputs unsorted SAM/BAM by default in older versions unless specified otherwise (but 0.7.x usually needs sort). 
    # We will use samtools index for .bai
    
    if [ ! -f "results/${SAMPLE}.bam.bai" ]; then
        samtools index "results/${SAMPLE}.bam" > /dev/null || true
    fi

done

# Variant Calling with LoFreq per sample (threads=4) and filtering/formatting with Bcftools
for SAMPLE in M117-bl M117-ch M117C1-bl M117C1-ch; do
    if [ -f "results/${SAMPLE}.vcf.gz" ]; then continue; fi

    # Call variants using LoFreq (threads=4) on the BAM file
    lofreq call -t ${THREADS} "results/${SAMPLE}.bam" > "results/tmp_${SAMPLE}_lofreq.vcf" 2>/dev/null || true
    
    # Compress and index VCF with Bcftools/Tabix logic
    if [ ! -f "results/${SAMPLE}.vcf.gz.tbi" ]; then
        gzip -k "results/tmp_${SAMPLE}_lofreq.vcf" > "results/${SAMPLE}.vcf.gz" 2>/dev/null || true
        
        # Index VCF with Tabix (or Bcftools index if available, but tabix is listed)
        tabix -p vcf -C "results/${SAMPLE}.vcf.gz.tbi" < /dev/null > /dev/null 2>&1 || \
            bcftools index "results/${SAMPLE}.vcf.gz" > /dev/null 2>&1 || true
        
        # Remove temp file if exists (cleanup)
        rm -f "results/tmp_${SAMPLE}_lofreq.vcf" 2>/dev/null || true
    fi

done

# Generate collapsed.tsv from all sample VCFs and header info
if [ ! -f "results/collapsed.tsv" ]; then
    
    # Extract columns: sample, chrom, pos, ref, alt, af (AF is in INFO field for LoFreq)
    # Use bcftools to extract specific fields if needed or standard awk/grep logic. 
    # Since we need AF from VCF header/INFO and it's a TSV output...
    
    # Create temporary directory for intermediate files per sample
    mkdir -p "results/tmp_collapse"

    for SAMPLE in M117-bl M117-ch M117C1-bl M117C1-ch; do
        if [ ! -f "results/${SAMPLE}.vcf.gz.tbi" ]; then continue; fi
        
        # Extract variants from VCF (using bcftools view to ensure format compliance) and filter for AF > 0.5 or similar? 
        # LoFreq output includes AF in INFO field usually.
        
        # Use tabix to extract regions if needed, but we need all variants.
        # We will use bcftools query to get columns directly into TSV per sample
        
        # Extract: CHROM\tPOS\tREF\tALT\tAF (from INFO) and SAMPLE name from filename or header? 
        # VCF has a HEADER line with sample names if multi-sample, but here we have single-sample files.
        # We need to tag the variant row with the Sample Name manually in TSV generation
        
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${SAMPLE}.vcf.gz" > "results/tmp_collapse/${SAMPLE}_variants.tsv" 2>/dev/null || true
    done

    # Combine all TSVs into one file with header and sample column prepended
    {
        printf 'sample\tsample\tchrom\tpos\tref\talt\taf\n'
        
        for SAMPLE in M117-bl M117-ch M117C1-bl M117C1-ch; do
            if [ -f "results/tmp_collapse/${SAMPLE}_variants.tsv" ]; then
                # Add sample name to each line (first column is chrom, so prepend)
                awk -v s="${SAMPLE}" '{print "\t"s\t$0}' "results/tmp_collapse/${SAMPLE}_variants.tsv" >> "results/collapsed.tsv.tmp" 2>/dev/null || true
            fi
        done
        
    } > "results/collapsed.tsv.tmp"

    mv "results/collapsed.tsv.tmp" "results/collapsed.tsv"

fi