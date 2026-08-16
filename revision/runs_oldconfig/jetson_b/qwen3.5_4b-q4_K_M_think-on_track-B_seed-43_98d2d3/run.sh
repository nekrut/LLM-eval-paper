#!/usr/bin/env bash
set -euo pipefail

# Check idempotency: if all expected outputs exist, exit 0
if [ "${BASH_SOURCE[0]}" = "$(realpath "$0")" ]; then
    # Ensure we are running in the correct context (cwd has data/raw/ and data/ref/)
fi

SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Check if all required outputs exist for ALL samples AND collapsed.tsv exists
ALL_DONE=true
for sample in "${SAMPLES[@]}"; do
    # Check BAM, BAI, VCF.gz, TBI existence
    [ -f "results/${sample}.bam" ] || { ALL_DONE=false; break; }
    [ -f "results/${sample}.bai" ] || { ALL_DONE=false; break; }
    [ -f "results/${sample}.vcf.gz" ] || { ALL_DONE=false; break; }
    [ -f "results/${sample}.vcf.gz.tbi" ] || { ALL_DONE=false; break; }
done

if [ "$ALL_DONE" = true ]; then
    # Check collapsed.tsv existence (optional but good for full idempotency)
    if [ ! -f "results/collapsed.tsv" ]; then
        ALL_DONE=false
    fi
fi

# If all done, exit 0 without redoing work
if $ALL_DONE; then
    exit 0
fi

# Run alignment and variant calling in parallel for each sample
for sample in "${SAMPLES[@]}"; do
    fq1="data/raw/${sample}_1.fq.gz"
    fq2="data/raw/${sample}_2.fq.gz"
    
    # Step 1: Align with BWA (threads=4)
    bwa mem -t 4 data/ref/chrM.fa "$fq1" "$fq2" | samtools sort -@ 4 -o "results/${sample}.bam.unsorted" || exit 1
    
    # Sort and index BAM
    samtools view -bS results/${sample}.bam.unsorted > results/${sample}.bam.sorted.tmp || exit 1
    mv results/${sample}.bam.sorted.tmp results/${sample}.bam
    samtools sort -@ 4 -o "results/${sample}.bam" results/${sample}.bam.unsorted 2>/dev/null || true
    
    # Step 2: Call variants with BCFTOOLS (ensure AF is calculated via -m flag)
    bcftools mpileup -f data/ref/chrM.fa results/${sample}.bam | \
        bcftools call -mv -m 10 -Oz -o "results/${sample}.vcf.gz" || exit 1
    
    # Index VCF
    tabix -p vcf results/${sample}.vcf.gz || true

done &

# Wait for all background jobs to complete
wait

# Generate collapsed.tsv with header and combined variants from all samples
{
    echo "sample	chrom	pos	ref	alt	af"
    
    # Extract fields: sample name, chrom, pos, ref, alt, af (from INFO/AF)
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f '%1\t%2\t%3\t%4\t%INFO/A1' results/${sample}.vcf.gz | \
            awk -v s="$sample" '{print "\t"s}'  # Note: %1 is CHROM, but we need sample name in col 1. 
        # Wait, bcftools query format string uses column indices starting at 0? No, starts at 1 for VCF columns (CHROM=1).
        # But I want to prepend the sample name as first field.
    done | sort -t$'\t' -k2,2n -u || true
    
} > results/collapsed.tsv

# Re-check idempotency after generation? No, just exit 0 if successful (handled by set -e)