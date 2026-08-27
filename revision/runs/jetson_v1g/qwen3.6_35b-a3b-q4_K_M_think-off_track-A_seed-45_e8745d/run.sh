#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"
REF_DIR="data/ref"
RAW_DIR="data/raw"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Step 2: Reference indexing (once)
if [ ! -f "${REF}.fai" ] || [ ! -f "${REF}.amb" ]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

# Step 3-7: Per-sample processing
for sample in "${SAMPLES[@]}"; do
    bam="${RESULTS_DIR}/${sample}.bam"
    bai="${bam}.bai"
    vcf="${RESULTS_DIR}/${sample}.vcf"
    vcf_gz="${vcf}.gz"
    tbi="${vcf_gz}.tbi"

    # Skip if all outputs exist and are newer than inputs
    if [ -f "$tbi" ] && \
       [ "$tbi" -nt "${bam}" ] 2>/dev/null && \
       [ "$tbi" -nt "${REF}" ] 2>/dev/null; then
        continue
    fi

    # Step 3 & 4: Alignment and sorting
    if [ ! -f "$bam" ]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "${REF}" \
            "${RAW_DIR}/${sample}_1.fq.gz" \
            "${RAW_DIR}/${sample}_2.fq.gz" | \
            samtools sort -@ "$THREADS" -o "$bam" -
    fi

    # Step 5: BAM indexing
    if [ ! -f "$bai" ]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    # Step 6: Variant calling with lofreq
    if [ ! -f "$vcf_gz" ]; then
        lofreq call-parallel --pp-threads "$THREADS" --verbose \
            --ref "$REF" \
            --out "$vcf" \
            --sig \
            --bonf \
            "$bam"
    fi

    # Step 7: VCF compression and indexing
    if [ ! -f "$tbi" ]; then
        bgzip -c "$vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf"
    fi
done

# Step 8: Collapse step
collapsed="${RESULTS_DIR}/collapsed.tsv"
need_collapse=false
if [ ! -f "$collapsed" ]; then
    need_collapse=true
else
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
        if [ "$vcf_gz" -nt "$collapsed" ] 2>/dev/null; then
            need_collapse=true
            break
        fi
    done
fi

if $need_collapse; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed"
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$vcf_gz" >> "$collapsed"
    done
fi