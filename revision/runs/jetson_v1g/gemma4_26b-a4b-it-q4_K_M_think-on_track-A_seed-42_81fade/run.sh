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

if [[ ! -t "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    F1="data/raw/${sample}_1.fq.gz"
    F2="data/raw/${sample}_2.fq.gz"
    BAM="$OUT_DIR/${sample}.bam"
    BAI="$OUT_DIR/${sample}.bam.bai"
    VCF_GZ="$OUT_DIR/${sample}.vcf.gz"
    TBI="$OUT_DIR/${sample}.vcf.gz.tbi"

    if [[ ! -f "$BAM" ]] || [[ "$F1" -nt "$BAM" ]] || [[ "${REF}.bwt" -nt "$BAM" ]]; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$REF" "$F1" "$F2" | \
        samtools sort -@ "$THREADS" -o "$BAM"
    fi

    if [[ ! -f "$BAI" ]] || [[ "$BAM" -nt "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    if [[ ! -f "$TBI" ]] || [[ "$BAM" -nt "$TBI" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" --verbose --ref "$REF" --out "$OUT_DIR/${sample}.vcf" --sig --bonf "$BAM"
        bgzip -c "$OUT_DIR/${sample}.vcf" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "$OUT_DIR/${sample}.vcf"
    fi
done

NEEDS_COLLAPSE=false
for sample in "${SAMPLES[@]}"; do
    TBI="$OUT_DIR/${sample}.vcf.gz.tbi"
    if [[ ! -f "$TBI" ]] || [[ "$TBI" -nt "$OUT_DIR/collapsed.tsv" ]]; then
        NEEDS_COLLAPSE=true
        break
    fi
done

if [ "$NEEDS_COLLAPSE" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$OUT_DIR/collapsed.tsv"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$OUT_DIR/${sample}.vcf.gz" >> "$OUT_DIR/collapsed.tsv" || true
    done
fi

exit 0