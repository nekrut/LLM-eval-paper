#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

# Step 2: Reference indexing (idempotent)
if [[ ! -f "${REF}.fai" ]] || [[ ! -f "${REF}.bwt" ]]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="${OUT_DIR}/${SAMPLE}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    # Check if final artifacts exist and are up-to-date
    # We check the TBI as the last artifact in the chain. 
    # If TBI exists, we assume VCF.GZ, BAM, BAI exist.
    # We also need to ensure BAM is newer than FASTQs for true idempotency on data changes, 
    # but strict file existence check is usually sufficient for "rerunning on populated results".
    if [[ -f "$TBI" ]]; then
        continue
    fi

    # Step 3 & 4: Alignment and Sorting
    # bwa mem with read group. Note the literal \t in the string as requested.
    RG="@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA"
    
    bwa mem -t "$THREADS" -R "$RG" "$REF" "${RAW_DIR}/${SAMPLE}_1.fq.gz" "${RAW_DIR}/${SAMPLE}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "$BAM"

    # Step 5: BAM Indexing
    samtools index -@ "$THREADS" "$BAM"

    # Step 6: Variant Calling with lofreq
    # Using call-parallel as requested. 
    # Note: lofreq call-parallel expects the BAM file as a positional argument at the end.
    lofreq call-parallel \
        --pp-threads "$THREADS" \
        --ref "$REF" \
        --out "${OUT_DIR}/${SAMPLE}.vcf" \
        "$BAM"

    # Step 7: VCF Compression and Indexing
    bgzip -c "${OUT_DIR}/${SAMPLE}.vcf" > "$VCF_GZ"
    tabix -p vcf "$VCF_GZ"
    
    # Remove intermediate uncompressed VCF
    rm -f "${OUT_DIR}/${SAMPLE}.vcf"
done

# Step 8: Collapse step -> results/collapsed.tsv
TSV="${OUT_DIR}/collapsed.tsv"

# Check if TSV needs rebuilding. 
# Rebuild if TSV doesn't exist or if any input VCF is newer than TSV.
NEED_REBUILD=false
if [[ ! -f "$TSV" ]]; then
    NEED_REBUILD=true
else
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$TSV" ]]; then
            NEED_REBUILD=true
            break
        fi
    done
fi

if $NEED_REBUILD; then
    # Create header
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$TSV"
    
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
        # bcftools query format: 
        # {sample} is literal text in the format string? No, we need to inject the sample name.
        # The prompt says: "the {sample} literal is prepended via the format string so the sample name is attached per row"
        # However, bcftools -f does not support variable substitution directly for the sample name inside the format string 
        # unless we use a placeholder or just print it.
        # Actually, bcftools query -f can take literal strings. We will construct the command to include the sample name literally.
        
        # Format: '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n'
        # We replace {sample} with the actual sample name in the bash variable expansion before passing to bcftools?
        # No, the prompt says "the {sample} literal is prepended via the format string". 
        # This implies we should use the literal string of the sample name in the format string.
        
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$TSV"
    done
fi