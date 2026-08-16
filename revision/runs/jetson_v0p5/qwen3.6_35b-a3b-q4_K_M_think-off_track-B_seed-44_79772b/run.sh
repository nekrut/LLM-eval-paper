#!/usr/bin/env bash
set -euo pipefail

# Create output directory
mkdir -p results

# Reference file path
REF="data/ref/chrM.fa"

# Check if reference index exists, create if not
if [ ! -f "${REF}.amb" ]; then
    bwa index "$REF"
fi

# Define samples and their read pairs
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

for SAMPLE in "${SAMPLES[@]}"; do
    R1="data/raw/${SAMPLE}_1.fq.gz"
    R2="data/raw/${SAMPLE}_2.fq.gz"
    BAM="results/${SAMPLE}.bam"
    VCF_GZ="results/${SAMPLE}.vcf.gz"

    # Skip if BAM already exists (idempotency)
    if [ -f "$BAM" ] && [ -f "${BAM}.bai" ] && [ -f "$VCF_GZ" ]; then
        continue
    fi

    # Step 1: Alignment with BWA-MEM
    bwa mem -t 4 "$REF" "$R1" "$R2" | samtools sort -@ 4 -o "$BAM" -
    
    # Step 2: Index BAM
    samtools index "$BAM"

    # Step 3: Variant calling with LoFreq (requires mpileup internally)
    # LoFreq calls variants and outputs VCF. We use --nproc to limit threads if needed, 
    # but since we are in a loop, single thread per sample is safer for resource control, 
    # though the prompt allows 4 threads total. We'll let lofreq handle its own threading.
    lofreq call -f "$REF" -i "$BAM" -o "${SAMPLE}.vcf.tmp" --no-indels
    
    # Filter out indels if strict SNP calling is implied by "variant calling" on chrM usually focusing on SNPs, 
    # but LoFreq outputs both. The prompt doesn't specify filtering. We keep all variants.
    
    # Step 4: Compress and index VCF with bcftools/tabix
    bcftools view -O z -o "$VCF_GZ" "${SAMPLE}.vcf.tmp"
    tabix -p vcf "$VCF_GZ"
    
    # Cleanup temp file
    rm -f "${SAMPLE}.vcf.tmp"

done

# Step 5: Collapse all VCFs into a single TSV
# Header
printf "sample\tchrom\tpos\tref\talt\taf\n" > results/collapsed.tsv

for SAMPLE in "${SAMPLES[@]}"; do
    VCF_GZ="results/${SAMPLE}.vcf.gz"
    
    # Extract INFO/AF and other fields. 
    # bcftools query format: %sample\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n
    # Note: AF might be missing or multi-value. We take the first value if present, else 0 or .
    # LoFreq outputs AF in INFO field as 'AF'.
    
    bcftools query -f '%SAMPLE\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$VCF_GZ" | \
    awk -F'\t' '{
        sample = $1; chrom = $2; pos = $3; ref = $4; alt = $5; af = $6;
        # Handle missing AF
        if (af == "." || af == "") af = "0";
        # LoFreq can output multiple alts separated by comma in ALT and corresponding AFs.
        # We need to split them into separate rows for a clean collapsed table.
        n_alt = split(alt, alt_arr, ",");
        n_af = split(af, af_arr, ",");
        
        if (n_alt != n_af) {
            # Fallback: just print the first one or join? Standard practice is one row per variant/allele.
            # If counts differ, it's an edge case. We'll assume they match for LoFreq output.
            n_alt = 1; 
            n_af = 1;
        }
        
        for (i=1; i<=n_alt; i++) {
            a = alt_arr[i];
            f = af_arr[i];
            if (f == "." || f == "") f = "0";
            printf "%s\t%s\t%s\t%s\t%s\t%s\n", sample, chrom, pos, ref, a, f;
        }
    }' >> results/collapsed.tsv

done