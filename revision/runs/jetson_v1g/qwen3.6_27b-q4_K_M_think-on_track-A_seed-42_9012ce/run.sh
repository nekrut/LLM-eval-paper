#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RAW=data/raw
RESULTS=results

mkdir -p "$RESULTS"

# Step 2: Reference indexing (idempotent)
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi
if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

# Steps 3-7: Per-sample processing
for sample in "${SAMPLES[@]}"; do
    TBI="${RESULTS}/${sample}.vcf.gz.tbi"

    # Skip if final artifact exists (idempotency guard)
    if [[ -f "$TBI" ]]; then
        continue
    fi

    BAM="${RESULTS}/${sample}.bam"
    VCF="${RESULTS}/${sample}.vcf"
    VCF_GZ="${RESULTS}/${sample}.vcf.gz"

    # Step 3+4: bwa mem | samtools sort
    bwa mem -t "$THREADS" \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        "$REF" \
        "${RAW}/${sample}_1.fq.gz" \
        "${RAW}/${sample}_2.fq.gz" | \
    samtools sort -@ "$THREADS" -o "$BAM"

    # Step 5: BAM indexing
    samtools index -@ "$THREADS" "$BAM"

    # Step 6: Variant calling with lofreq call-parallel
    lofreq call-parallel --pp-threads "$THREADS" \
        --ref "$REF" \
        --out "$VCF" \
        "$BAM"

    # Step 7: Compress and index VCF
    bgzip -c "$VCF" > "$VCF_GZ"
    tabix -p vcf "$VCF_GZ"
    rm -f "$VCF"
done

# Step 8: Collapse step -> results/collapsed.tsv
COLLAPSED="${RESULTS}/collapsed.tsv"
REBUILD=0
for sample in "${SAMPLES[@]}"; do
    VCF_GZ="${RESULTS}/${sample}.vcf.gz"
    if [[ ! -f "$COLLAPSED" ]] || [[ "$VCF_GZ" -nt "$COLLAPSED" ]]; then
        REBUILD=1
        break
    fi
done

if [[ "$REBUILD" -eq 1 ]]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
                "${RESULTS}/${sample}.vcf.gz"
        done
    } > "$COLLAPSED"
fi