#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
OUT_DIR="results"

mkdir -p "$OUT_DIR"

if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

BWA_INDEX_EXISTS=false
for ext in amb ann bwt pac sa; do
    if [[ ! -f "${REF}.${ext}" ]]; then
        BWA_INDEX_EXISTS=false
        break
    else
        BWA_INDEX_EXISTS=true
    fi
done

if [ "$BWA_INDEX_EXISTS" = false ]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    FQ1="data/raw/${sample}_1.fq.gz"
    FQ2="data/raw/${sample}_2.fq.gz"
    BAM="$OUT_DIR/${sample}.bam"
    BAI="$OUT_DIR/${sample}.bam.bai"
    VCF_GZ="$OUT_DIR/${sample}.vcf.gz"
    TBI="$OUT_DIR/${sample}.vcf.gz.tbi"

    if [[ -f "$TBI" && "$TBI" -nt "$FQ1" && "$TBI" -nt "$FQ2" ]]; then
        continue
    fi

    RG_STR="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
    
    bwa mem -t "$THREADS" -R "$RG_STR" "$REF" "$FQ1" "$FQ2" | \
        samtools sort -@ "$THREADS" -o "$BAM"

    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    VCF_UNCOMPRESSED="$OUT_DIR/${sample}.vcf"
    if [[ ! -f "$VCF_GZ" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF_UNCOMPRESSED" "$BAM"
        
        # bgzip is part of htslib/samtools ecosystem, using samtools view for compression if bgzip not explicitly in inventory but standard with samtools
        # The prompt implies bgzip usage; since it's part of the same suite as samtools/tabix:
        samtools view -u "$VCF_UNCOMPRESSED" | bgzip -@ "$THREADS" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "$VCF_UNCOMPRESSED"
    fi
done

TSV="$OUT_DIR/collapsed.tsv"
NEEDS_TSV=true
for sample in "${SAMPLES[@]}"; do
    if [[ ! -f "$OUT_DIR/${sample}.vcf.gz.tbi" || "$TSV" -nt "$OUT_DIR/${sample}.vcf.gz.tbi" ]]; then
        NEEDS_TSV=true
        break
    fi
done

if [ "$NEEDS_TSV" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$TSV"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$OUT_DIR/${sample}.vcf.gz" >> "$TSV"
    done
fi

exit 0