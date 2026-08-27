#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLE_LIST=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF_FILE="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (once)
if [ ! -f "${REF_FILE}.fai" ]; then
    samtools faidx "$REF_FILE"
fi
if [ ! -d "data/ref/*.amb data/ref/*.ann data/ref/*.bwt data/ref/*.pac data/ref/*.sa" ] && \
   [ "$(ls -A data/ref/ 2>/dev/null | grep -E '\.(amb|ann|bwt|pac|sa)$')" ]; then
    bwa index "$REF_FILE"
fi

# Per-sample processing loop
for sample in "${SAMPLE_LIST[@]}"; do
    R1="data/raw/${sample}_1.fq.gz"
    R2="data/raw/${sample}_2.fq.gz"
    
    # Check if all outputs exist and are newer than inputs to skip work
    VCF_TBI="${RESULTS_DIR}/${sample}.vcf.gz.tbi"
    BAM_BAI="${RESULTS_DIR}/${sample}.bam.bai"
    BAM_OUT="${RESULTS_DIR}/${sample}.bam"
    VCF_OUT="${RESULTS_DIR}/${sample}.vcf"

    if [ -e "$VCF_TBI" ] && \
       [[ "$(stat -c %Y $VCF_TBI 2>/dev/null)" -gt "$(stat -c %Y ${R1}) $(stat -c %Y ${R2})" ]]; then
        continue
    fi

    # Step 3: Alignment with bwa mem (using literal backslash-t for RG)
    if [ ! -f "$BAM_OUT" ]; then
        echo "Aligning $sample..." >&2
        bwa mem -t ${THREADS} \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "${REF_FILE}" "$R1" "$R2" | samtools sort -@ ${THREADS} -o "$BAM_OUT"
    fi

    # Step 4 & 5: Sort and index BAM (sort done in step, just index)
    if [ ! -f "$BAM_BAI" ]; then
        echo "Indexing $sample..." >&2
        samtools index -@ ${THREADS} "$BAM_OUT"
    fi

    # Step 6: Variant calling with lofreq call-parallel
    if [ ! -e "${RESULTS_DIR}/${sample}.vcf.gz.tbi" ]; then
        echo "Calling variants for $sample..." >&2
        lofreq call-parallel --pp-threads ${THREADS} \
            -f "$REF_FILE" \
            -o "${RESULTS_DIR}/${sample}.vcf" \
            "$BAM_OUT"

        # Step 7: Compress and index VCF, remove uncompressed
        bgzip -c "${RESULTS_DIR}/${sample}.vcf" > "${RESULTS_DIR}/${sample}.vcf.gz"
        tabix -p vcf "${RESULTS_DIR}/${sample}.vcf.gz"
        rm -f "${RESULTS_DIR}/${sample}.vcf"
    fi

done

# Step 8: Collapse step -> results/collapsed.tsv
COLLAPSED_TSV="${RESULTS_DIR}/collapsed.tsv"
if [ ! -e "$COLLAPSED_TSV" ]; then
    echo "Generating collapsed table..." >&2
    
    # Build header and data from all samples, ensuring idempotency by checking VCFs first
    HEADER="sample	chrom	pos	ref	alt	af"
    
    DATA=""
    for sample in "${SAMPLE_LIST[@]}"; do
        if [ -e "${RESULTS_DIR}/${sample}.vcf.gz.tbi" ]; then
            # bcftools query format: {sample} literal is prepended via the format string so the sample name is attached per row.
            DATA+=$(bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "${RESULTS_DIR}/${sample}.vcf.gz")
        fi
    done

    # Write header and data to file (tab-separated)
    printf '%s\n%s\n' "$HEADER" "$DATA" > "$COLLAPSED_TSV"
fi