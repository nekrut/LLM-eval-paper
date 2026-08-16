#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
RAW_DIR="data/raw"
REF_DIR="data/ref"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

if [[ ! -f "$REF_DIR/chrM.fa.fai" ]]; then
    samtools faidx "$REF_DIR/chrM.fa"
fi

if [[ ! -f "$REF_DIR/chrM.fa.bwt" ]]; then
    bwa index "$REF_DIR/chrM.fa"
fi

for sample in "${SAMPLES[@]}"; do
    bam_file="$RESULTS_DIR/${sample}.bam"
    if [[ ! -f "$bam_file" ]]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF_DIR/chrM.fa" \
            "$RAW_DIR/${sample}_1.fq.gz" \
            "$RAW_DIR/${sample}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "$bam_file"
    fi
    
    bai_file="${bam_file}.bai"
    if [[ ! -f "$bai_file" ]]; then
        samtools index -@ "$THREADS" "$bam_file"
    fi
done

for sample in "${SAMPLES[@]}"; do
    vcf_file="$RESULTS_DIR/${sample}.vcf"
    vcf_gz_file="${vcf_file}.gz"
    vcf_tbi_file="${vcf_gz_file}.tbi"
    bam_file="$RESULTS_DIR/${sample}.bam"
    
    if [[ ! -f "$vcf_tbi_file" ]]; then
        rm -f "$vcf_file" "$vcf_gz_file"
        lofreq call-parallel --pp-threads "$THREADS" --verbose \
            --ref "$REF_DIR/chrM.fa" --out "$vcf_file" \
            "$bam_file"
        
        bgzip -f "$vcf_file"
        tabix -p vcf "$vcf_gz_file"
    fi
done

collapsed_file="$RESULTS_DIR/collapsed.tsv"
rebuild_collapsed=false

if [[ ! -f "$collapsed_file" ]]; then
    rebuild_collapsed=true
else
    for sample in "${SAMPLES[@]}"; do
        vcf_gz_file="$RESULTS_DIR/${sample}.vcf.gz"
        if [[ "$vcf_gz_file" -nt "$collapsed_file" ]]; then
            rebuild_collapsed=true
            break
        fi
    done
fi

if [[ "$rebuild_collapsed" == "true" ]]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${SAMPLES[@]}"; do
            vcf_gz_file="$RESULTS_DIR/${sample}.vcf.gz"
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$vcf_gz_file"
        done
    } > "$collapsed_file"
fi