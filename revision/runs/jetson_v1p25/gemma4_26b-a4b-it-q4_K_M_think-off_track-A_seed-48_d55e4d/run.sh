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

BWA_INDEXES=("${REF}.amb" "${REF}.ann" "${REF}.bwt" "${REF}.pac" "${REF}.sa")
ALL_BWA_EXISTS=true
for idx in "${BWA_INDEXES[@]}"; do
    if [[ ! -f "$idx" ]]; then
	    ALL_BWA_EXISTS=false
	    break
    fi
done

if [ "$ALL_BWA_EXISTS" = false ]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    BAM="$OUT_DIR/${sample}.bam"
    BAI="$OUT_DIR/${sample}.bam.bai"
    VCF_GZ="$OUT_DIR/${sample}.vcf.gz"
    VCF_TBI="$OUT_DIR/${sample}.vcf.gz.tbi"
    R1="data/raw/${sample}_1.fq.gz"
    R2="data/raw/${sample}_2.fq.gz"

    if [[ ! -f "$VCF_TBI" ]]; then
        if [[ ! -f "$BAM" ]] || [[ "$R1" -nt "$BAM" ]] || [[ "$R2" -nt "$BAM" ]]; then
            RG="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
            bwa mem -t "$THREADS" -R "$RG" "$REF" "$R1" "$R2" | \
                samtools sort -@ "$THREADS" -o "$BAM"
        fi

        if [[ ! -f "$BAI" ]] || [[ "$BAM" -nt "$BAI" ]]; then
            samtools index -@ "$THREADS" "$BAM"
        fi

        VCF_UNCOMPRESSED="$OUT_DIR/${sample}.vcf"
        if [[ ! -f "$VCF_UNCOMPRESSED" ]] || [[ "$BAM" -nt "$VCF_UNCOMPRESSED" ]]; then
            lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF_UNCOMPRESSED" "$BAM"
        fi

        if [[ ! -f "$VCF_GZ" ]] || [[ "$VCF_UNCOMPRESSED" -nt "$VCF_GZ" ]]; then
            bgzip -c "$VCF_UNCOMPRESSED" > "$VCF_GZ"
            rm "$VCF_UNCOMPRESSED"
        fi

        if [[ ! -f "$VCF_TBI" ]] || [[ "$VCF_GZ" -nt "$VCF_TBI" ]]; then
            tabix -p vcf "$VCF_GZ"
        fi
    fi
done

TSV="$OUT_DIR/collapsed.tsv"
NEEDS_TSV=true
for sample in "${SAMPLES[@]}"; do
    if [[ ! -f "$TSV" ]] || [[ "$OUT_DIR/${sample}.vcf.gz.tbi" -nt "$TSV" ]]; then
        NEEDS_TSV=false
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