#!/usr/bin/env bash
set -euo pipefail

# Configuration
THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
RES_DIR="results"

# Create results directory if missing
mkdir -p "$RES_DIR"

# Function to check if target needs updating based on source files
# Returns 0 (true) if update is needed, 1 (false) if not
needs_update() {
    local target="$1"
    shift
    # If target does not exist, it needs to be created
    if [[ ! -f "$target" ]]; then
        return 0
    fi
    # Check if any source file is newer than the target
    for src in "$@"; do
        if [[ "$src" -nt "$target" ]]; then
            return 0
        fi
    done
    return 1
}

# Step 2: Reference Indexing
# samtools faidx
if needs_update "${REF}.fai" "$REF"; then
    samtools faidx "$REF"
fi

# bwa index (check for .bwt as a proxy for the index set)
if needs_update "${REF}.bwt" "$REF"; then
    bwa index "$REF"
fi

# Loop over samples
for sample in "${SAMPLES[@]}"; do
    R1="${RAW_DIR}/${sample}_1.fq.gz"
    R2="${RAW_DIR}/${sample}_2.fq.gz"
    BAM="${RES_DIR}/${sample}.bam"
    BAI="${RES_DIR}/${sample}.bam.bai"
    VCF_GZ="${RES_DIR}/${sample}.vcf.gz"
    TBI="${RES_DIR}/${sample}.vcf.gz.tbi"
    VCF_TMP="${RES_DIR}/${sample}.vcf"

    # Step 3 & 4: Alignment and Sorting
    # Inputs: R1, R2, Reference Index (.bwt)
    if needs_update "$BAM" "$R1" "$R2" "${REF}.bwt"; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" "$R1" "$R2" | \
        samtools sort -@ "$THREADS" -o "$BAM" -
    fi

    # Step 5: BAM Indexing
    if needs_update "$BAI" "$BAM"; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # Step 6 & 7: Variant Calling, Compression, Indexing
    # We check the final compressed VCF. If it exists and is newer than BAM/Ref, skip.
    if needs_update "$VCF_GZ" "$BAM" "$REF"; then
        # Call variants (outputs uncompressed VCF)
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF_TMP" "$BAM"

        # Compress with bgzip
        bgzip -c "$VCF_TMP" > "${VCF_GZ}.tmp" && mv "${VCF_GZ}.tmp" "$VCF_GZ"

        # Index VCF
        tabix -p vcf "$VCF_GZ"

        # Remove intermediate uncompressed VCF
        rm -f "$VCF_TMP"
    fi
done

# Step 8: Collapse
COLLAPSED="${RES_DIR}/collapsed.tsv"
VCFS=()
for sample in "${SAMPLES[@]}"; do
    VCFS+=("${RES_DIR}/${sample}.vcf.gz")
done

if needs_update "$COLLAPSED" "${VCFS[@]}"; then
    # Write header
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"

    for sample in "${SAMPLES[@]}"; do
        VCF_FILE="${RES_DIR}/${sample}.vcf.gz"
        # Query VCF and prepend sample name
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_FILE" >> "$COLLAPSED"
    done
fi