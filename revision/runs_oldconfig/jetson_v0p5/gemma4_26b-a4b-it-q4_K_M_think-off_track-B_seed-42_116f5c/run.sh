#!/usr/bin/env bash
set -euo pipefail

# Configuration
THREADS=4
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
OUT_DIR="results"
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Create output directory
mkdir -p "$OUT_DIR"

# Index reference if not present
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

# Process each sample
for SAMPLE in "${SAMPLES[@]}"; do
    BAM="$OUT_DIR/${SAMPLE}.bam"
    VCF="$OUT_DIR/${SAMPLE}.vcf.gz"

    if [[ -f "$VCF" && -f "$BAM.bai" ]]; then
        continue
    fi

    # Alignment
    bwa mem -t "$THREADS" -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tPL:ILLUMINA" \
        "$REF" \
        "${RAW_DIR}/${SAMPLE}_1.fq.gz" \
        "${RAW_DIR}/${SAMPLE}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "$BAM" -

    samtools index "$BAM"

    # Variant Calling using lofreq
    # lofreq requires a bed file or uses whole genome; for chrM we use the ref
    # We'll create a small bed for chrM to speed up and ensure coverage
    CHR_BED=$(mktemp)
    samtools faidx "$REF" | awk '{print $1"\t"NR-1"\t"$2}' > "$CHR_BED"

    lofreq call -f "$REF" -b "$CHR_BED" -o "$VCF" "$BAM"
    
    # lofreq output is not compressed/indexed by default in all versions, 
    # but the task requires .vcf.gz and .tbi
    if [[ ! -f "${VCF}.gz" ]]; then
        bgzip -c "$VCF" > "${VCF}.gz"
        rm "$VCF"
        tabix -p vcf "${VCF}.gz"
    fi

    rm "$CHR_BED"
done

# Create collapsed table
COLLAPSED="$OUT_DIR/collapsed.tsv"
if [[ ! -f "$COLLAPSED" ]]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$COLLAPSED"
    
    for SAMPLE in "${SAMPLES[@]}"; do
        VCF_IN="$OUT_DIR/${SAMPLE}.vcf.gz"
        if [[ -f "$VCF_IN" ]]; then
            # Extracting: CHROM, POS, REF, ALT, and AF (from INFO field)
            # lofreq stores AF in the INFO field as AF=...
            bcftools query -f "%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_IN" | \
            awk -v smp="$SAMPLE" '{print smp"\t"$0}' >> "$COLLAPSED"
        fi
    done

    # Clean up potential empty lines or malformed AF (if AF is missing, use 0)
    sed -i '/\t$/d' "$COLLAPSED"
    # Ensure tab separation and handle cases where AF might be empty/NA
    tmp_tsv=$(mktemp)
    head -n 1 "$COLLAPSED" > "$tmp_tsv"
    tail -n +2 "$COLLAPSED" | awk -F'\t' 'BEGIN{OFS="\t"} {if($5==".") $5="0"; print $0}' >> "$tmp_tsv"
    mv "$tmp_tsv" "$COLLAPSED"
fi

exit 0