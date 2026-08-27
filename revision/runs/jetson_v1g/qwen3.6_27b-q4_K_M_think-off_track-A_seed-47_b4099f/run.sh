#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
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

    # Check if final artifacts exist and are up-to-date to skip work (idempotency)
    # We check the final compressed/indexed VCF. If it exists, we assume the pipeline is done for this sample.
    if [[ -f "$TBI" ]]; then
        continue
    fi

    R1="${RAW_DIR}/${SAMPLE}_1.fq.gz"
    R2="${RAW_DIR}/${SAMPLE}_2.fq.gz"

    # Step 3 & 4: Alignment and Sorting
    # bwa mem with read group, piped to samtools sort
    # Note: The prompt specifies using literal \t in the RG string for bwa.
    bwa mem -t "$THREADS" -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" "$REF" "$R1" "$R2" | \
        samtools sort -@ "$THREADS" -o "$BAM"

    # Step 5: BAM indexing
    samtools index -@ "$THREADS" "$BAM"

    # Step 6: Variant calling with lofreq call-parallel
    # Using the IUC-derived snippet structure.
    # --sig and --bonf are omitted as per instructions to use defaults if not load-bearing, 
    # but keeping --pp-threads and verbose for robustness.
    lofreq call-parallel \
        --pp-threads "$THREADS" \
        --verbose \
        --ref "$REF" \
        --out "${OUT_DIR}/${SAMPLE}.vcf" \
        "$BAM"

    # Step 7: VCF compression and indexing
    bgzip -c "${OUT_DIR}/${SAMPLE}.vcf" > "$VCF_GZ"
    tabix -p vcf "$VCF_GZ"
    
    # Remove intermediate uncompressed VCF
    rm -f "${OUT_DIR}/${SAMPLE}.vcf"
done

# Step 8: Collapse step -> results/collapsed.tsv
TSV="${OUT_DIR}/collapsed.tsv"

# Check if TSV needs rebuilding. 
# It needs rebuilding if it doesn't exist, or if any input VCF is newer than the TSV.
REBUILD_TSV=false
if [[ ! -f "$TSV" ]]; then
    REBUILD_TSV=true
else
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
        if [[ "$VCF_GZ" -nt "$TSV" ]]; then
            REBUILD_TSV=true
            break
        fi
    done
fi

if $REBUILD_TSV; then
    # Create header
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$TSV"
    
    # Append data from each sample
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_GZ="${OUT_DIR}/${SAMPLE}.vcf.gz"
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$TSV"
    done
fi