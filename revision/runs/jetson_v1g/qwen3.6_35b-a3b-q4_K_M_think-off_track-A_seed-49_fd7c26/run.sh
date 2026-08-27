#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"
RAW_DIR="data/raw"
REF_DIR="data/ref"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Step 2: Reference indexing (idempotent)
if [ ! -f "${REF}.fai" ] || [ ! -f "${REF}.amb" ]; then
    samtools faidx "${REF}"
    bwa index "${REF}"
fi

# Step 3-5: Alignment, Sorting, Indexing per sample
for sample in "${SAMPLES[@]}"; do
    bam_file="${RESULTS_DIR}/${sample}.bam"
    bai_file="${bam_file}.bai"
    
    if [ ! -f "$bai_file" ] || [ "$RAW_DIR/${sample}_1.fq.gz" -nt "$bam_file" -o "$REF" -nt "$bam_file" ]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "${REF}" \
            "${RAW_DIR}/${sample}_1.fq.gz" \
            "${RAW_DIR}/${sample}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "$bam_file" -
        
        samtools index -@ "$THREADS" "$bam_file"
    fi
done

# Step 6-7: Variant calling, Compression, Indexing per sample
for sample in "${SAMPLES[@]}"; do
    vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
    tbi_file="${vcf_gz}.tbi"
    vcf_plain="${RESULTS_DIR}/${sample}.vcf"
    bam_file="${RESULTS_DIR}/${sample}.bam"
    
    if [ ! -f "$tbi_file" ] || [ "$bam_file" -nt "$vcf_gz" ]; then
        lofreq call-parallel --pp-threads "$THREADS" --verbose \
            --ref "${REF}" \
            --out "${vcf_plain}" \
            --sig \
            --bonf \
            "${bam_file}"
        
        bgzip -f "${vcf_plain}"
        tabix -p vcf "${vcf_gz}"
    fi
done

# Step 8: Collapse VCFs into TSV
collapsed_tsv="${RESULTS_DIR}/collapsed.tsv"
header="sample	chrom	pos	ref	alt	af"

# Check if we need to rebuild the collapsed file
need_rebuild=false
for sample in "${SAMPLES[@]}"; do
    vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
    if [ ! -f "$collapsed_tsv" ] || [ "$vcf_gz" -nt "$collapsed_tsv" ]; then
        need_rebuild=true
        break
    fi
done

if [ "$need_rebuild" = true ]; then
    echo -e "$header" > "$collapsed_tsv"
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="${RESULTS_DIR}/${sample}.vcf.gz"
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${vcf_gz}" >> "$collapsed_tsv"
    done
fi