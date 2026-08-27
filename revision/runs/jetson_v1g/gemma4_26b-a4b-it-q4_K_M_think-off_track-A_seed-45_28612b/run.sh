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

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    FQ1="data/raw/${sample}_1.fq.gz"
    FQ2="data/raw/${sample}_2.fq.gz"
    BAM="$OUT_DIR/${sample}.bam"
    VCF_GZ="$OUT_DIR/${sample}.vcf.gz"
    VCF_TBI="$OUT_DIR/${sample}.vcf.gz.tbi"

    if [[ -f "$VCF_TBI" && "$VCF_TBI" -nt "$FQ1" && "$VCF_TBI" -nt "$FQ2" ]]; then
        continue
    fi

    if [[ ! -f "$BAM" || "$BAM" -nt "$FQ1" || "$BAM" -nt "$FQ2" ]]; then
        RG="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
        bwa mem -t "$THREADS" -R "$RG" "$REF" "$FQ1" "$FQ2" | \
            samtools sort -@ "$THREADS" -o "$BAM"
    fi

    if [[ ! -f "${BAM}.bai" || "${BAM}.bai" -nt "$BAM" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    if [[ ! -f "$VCF_GZ" || "$VCF_GZ" -nt "$BAM" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" \
            --ref "$REF" \
            --out "$OUT_DIR/${sample}.vcf" \
            --sig \
            --bonf \
            "$BAM"
        
        bgzip -c "$OUT_DIR/${sample}.vcf" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "$OUT_DIR/${sample}.vcf"
    fi
done

TSV="$OUT_DIR/collapsed.tsv"
NEEDS_COLLAPSE=false
if [[ ! -f "$TSV" ]]; then
    NEEDS_COLLAPSE=true
else
    for sample in "${SAMPLES[@]}"; do
        if [[ ! -f "$OUT_DIR/${sample}.vcf.gz.tbi" || "$OUT_DIR/${sample}.vcf.gz.tbi" -nt "$TSV" ]]; then
            NEEDS_COLLAPSE=true
            break
        fi
    done
fi

if [ "$NEEDS_COLLAPSE" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$TSV"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$OUT_DIR/${sample}.vcf.gz" >> "$TSV"
    done
fi

exit 0