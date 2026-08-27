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
    VCF_TBI="$OUT_DIR/${sample}.vcf.gz.tbi"

    if [[ -f "$VCF_TBI" && "$VCF_TBI" -nt "$FQ1" && "$VCF_TBI" -nt "$FQ2" ]]; then
        continue
    fi

    RG_STR="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
    
    bwa mem -t "$THREADS" -R "$RG_STR" "$REF" "$FQ1" "$FQFS2" 2>/dev/null | \
        samtools sort -@ "$THREADS" -o "$BAM"

    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    VCF_UNCOMPRESSED="$OUT_DIR/${sample}.vcf"
    if [[ ! -f "$VCF_GZ" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF_UNCOMPRESSED" "$BAM"
        
        # bgzip is part of htslib/samtools ecosystem, using samtools view to compress if bgzip not explicitly in inventory but standard for vcf.gz
        # The prompt specifies: Compress with `bgzip` (not `bcftools view -O z`)
        # Since bgzip is the tool requested and part of htslib/samtools suite:
        bgzip -f "$VCF_UNCOMPRESSED"
        
        tabix -p vcf "$VCF_GZ"
    fi
done

TSV_OUT="$OUT_DIR/collapsed.tsv"
NEEDS_COLLAPSE=true
for sample in "${SAMPLES[@]}"; do
    if [[ ! -f "$OUT_DIR/${sample}.vcf.gz.tbi" ]]; then
        NEEDS_COLLAPSE=false
        break
    fi
    if [[ "$TSV_OUT" -e ]] && [[ "$OUT_DIR/${sample}.vcf.gz.tbi" -nt "$TSV_OUT" ]]; then
        NEEDS_COLLAPSE=true
        break
    fi
done

if [ "$NEEDS_COLLAPSE" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$TSV_OUT"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$OUT_DIR/${sample}.vcf.gz" >> "$TSV_OUT"
    done
fi

exit 0