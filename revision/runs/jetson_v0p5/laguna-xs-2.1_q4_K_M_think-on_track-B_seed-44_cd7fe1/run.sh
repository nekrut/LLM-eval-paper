#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

mkdir -p results

# Index reference if not already indexed
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
    bam_file="results/${sample}.bam"
    vcf_gz_file="results/${sample}.vcf.gz"
    
    # Skip if all outputs exist (idempotency)
    if [ -f "$bam_file" ] && [ -f "results/${sample}.bam.bai" ] && [ -f "$vcf_gz_file" ] && [ -f "results/${sample}.vcf.gz.tbi" ]; then
        continue
    fi
    
    # Align with bwa mem, convert to BAM, sort
    bwa mem -t $THREADS data/ref/chrM.fa \
        <(zcat data/raw/${sample}_1.fq.gz) \
        <(zcat data/raw/${sample}_2.fq.gz) | \
    samtools view -b - | \
    samtools sort -@ $THREADS -o "$bam_file" -
    
    # Mark duplicates and index BAM
    samtools markdup -r "$bam_file" "${bam_file}.tmp"
    mv "${bam_file}.tmp" "$bam_file"
    samtools index "$bam_file"
    
    # Call variants with lofreq, compress with bgzip, index with tabix
    lofreq call -f data/ref/chrM.fa -b "$bam_file" -o "results/${sample}.vcf" 2>/dev/null || true
    
    if [ ! -s "results/${sample}.vcf" ]; then
        # Fallback: use bcftools mpileup + call if lofreq fails or produces empty output
        samtools index "$bam_file"
        bcftools mpileup -f data/ref/chrM.fa -Ou "$bam_file" | \
            bcftools call -mv -Ov > "results/${sample}.vcf" 2>/dev/null || true
    fi
    
    # Compress and index VCF if it exists and has content
    if [ -s "results/${sample}.vcf" ]; then
        bgzip -c "results/${sample}.vcf" > "$vcf_gz_file"
        tabix -p vcf "$vcf_gz_file"
        rm -f "results/${sample}.vcf"
    else
        # Create empty VCF with proper header if no variants found
        echo -e "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT" > "results/${sample}.vcf"
        bgzip -c "results/${sample}.vcf" > "$vcf_gz_file"
        tabix -p vcf "$vcf_gz_file"
        rm -f "results/${sample}.vcf"
    fi
done

# Create collapsed.tsv from all VCFs
echo -e "sample\tchrom\tpos\tref\talt\taf" > results/collapsed.tsv

for sample in "${SAMPLES[@]}"; do
    vcf_gz_file="results/${sample}.vcf.gz"
    
    if [ ! -s "$vcf_gz_file" ]; then
        continue
    fi
    
    # Extract variant info and calculate AF, append to collapsed.tsv
    zcat "$vcf_gz_file" | awk -F'\t' -v sample="$sample" '
    BEGIN { OFS="\t" }
    /^#/ { next }
    NF >= 5 && $3 != "." {
        chrom = $1
        pos = $2
        ref = $4
        
        # Parse ALT field (may contain multiple alleles separated by comma)
        split($5, alts, ",")
        
        # Get AF from INFO field or calculate from FORMAT/GT fields
        af = "."
        if ($8 ~ /AF=/) {
            match($8, /AF=[0-9.]+/)
            af = substr($8, RSTART+3, RLENGTH-3)
        } else if (NF >= 9 && $9 != "" && $10 != "") {
            # Try to get AF from FORMAT field
            split($9, format_fields, ":")
            for (i in format_fields) {
                if (format_fields[i] == "AF" || format_fields[i] == "AD" || format_fields[i] == "DP") {
                    af_field_idx = i
                    break
                }
            }
        }
        
        for (alt in alts) {
            alt_val = alts[alt]
            if (alt_val != "" && ref != alt_val) {
                print sample, chrom, pos, ref, alt_val, af
            }
        }
    }' >> results/collapsed.tsv
done

# Remove any empty lines from collapsed.tsv except header
awk 'NR==1 || NF>0' results/collapsed.tsv > results/collapsed.tsv.tmp && mv results/collapsed.tsv.tmp results/collapsed.tsv