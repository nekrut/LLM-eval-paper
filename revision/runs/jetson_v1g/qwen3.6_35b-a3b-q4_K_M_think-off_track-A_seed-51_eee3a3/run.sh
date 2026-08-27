#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"

mkdir -p results

# Step 2: Reference indexing (idempotent)
if [ ! -f "data/ref/chrM.fa.fai" ]; then
    samtools faidx "$REF"
fi
if [ ! -f "data/ref/chrM.fa.amb" ]; then
    bwa index "$REF"
fi

# Step 3-5: Per-sample alignment, sorting, indexing
for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    bai="${bam}.bai"
    vcf_gz="results/${sample}.vcf.gz"
    tbi="${vcf_gz}.tbi"

    # Skip if BAM and BAI already exist
    if [ -f "$bam" ] && [ -f "$bai" ]; then
        continue
    fi

    fq1="data/raw/${sample}_1.fq.gz"
    fq2="data/raw/${sample}_2.fq.gz"

    # Step 3 & 4: Align and sort
    bwa mem -t "$THREADS" \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        "$REF" "$fq1" "$fq2" | \
        samtools sort -@ "$THREADS" -o "$bam" -

    # Step 5: Index BAM
    samtools index -@ "$THREADS" "$bam"
done

# Step 6-7: Per-sample variant calling, compression, indexing
for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    vcf_gz="results/${sample}.vcf.gz"
    tbi="${vcf_gz}.tbi"

    # Skip if VCF.GZ and TBI already exist
    if [ -f "$vcf_gz" ] && [ -f "$tbi" ]; then
        continue
    fi

    vcf="results/${sample}.vcf"

    # Step 6: Call variants
    lofreq call-parallel --pp-threads "$THREADS" --verbose \
        --ref "$REF" --out "$vcf" \
        --sig --bonf \
        "$bam"

    # Step 7: Compress and index VCF
    bgzip -f "$vcf"
    tabix -p vcf "$vcf_gz"
done

# Step 8: Collapse variants into TSV
collapsed="results/collapsed.tsv"
need_collapse=0

for sample in "${SAMPLES[@]}"; do
    vcf_gz="results/${sample}.vcf.gz"
    if [ ! -f "$vcf_gz" ]; then
        need_collapse=1
        break
    fi
done

if [ ! -f "$collapsed" ] || [ "$need_collapse" -eq 1 ]; then
    # Write header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed"
    
    # Append data from each sample
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="results/${sample}.vcf.gz"
        if [ -f "$vcf_gz" ]; then
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$vcf_gz" >> "$collapsed"
        fi
    done
fi