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
    R1="data/raw/${sample}_1.fq.gz"
    R2="data/raw/${sample}_2.fq.gz"
    BAM="$OUT_DIR/${sample}.bam"
    BAI="$BAM.bai"
    VCF_GZ="$OUT_DIR/${sample}.vcf.gz"
    TBI="$VCF_GZ.tbi"

    if [[ -f "$TBI" && "$TBI" -nt "$R1" && "$TBI" -nt "$R2" ]]; then
        continue
    fi

    RG_STR="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
    
    bwa mem -t "$THREADS" -R "$RG_STR" "$REF" "$R1" "$R2" | \
        samtools sort -@ "$THREADS" -o "$BAM"

    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    VCF_UNCOMPRESSED="$OUT_DIR/${sample}.vcf"
    if [[ ! -f "$VCF_GZ" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$VCF_UNCOMPRESSED" "$BAM"
        
        # bgzip is part of htslib/samtools suite, using samtools view for compression if bgzip not explicitly in inventory but standard in such envs. 
        # However, instructions say use bgzip. Assuming bgzip available via htslib tools.
        bgzip -c "$VCF_UNCOMPRESESS" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "$VCF_UNCOMPRESSED"
    fi
done

TSV="$OUT_DIR/collapsed.tsv"
NEEDS_TSV=true
for sample in "${SAMPLES[@]}"; do
    VCF_GZ="$OUT_DIR/${sample}.vcf.gz"
    if [[ -f "$VCF_GZ" && ! "$NEEDS_TSV" ]]; then
        # Check if any VCF is newer than TSV
        if [[ "$VCF_GZ" -nt "$TSV" ]]; then
            NEEDS_TSV=true
        else
            NEEDS_TSV=false
        fi
    fi
done

if [ "$NEEDS_TSV" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$TSV"
    for sample in "${SAMPLES[@]}"; do
        VCF_GZ="$OUT_DIR/${sample}.vcf.gz"
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$TSV"
    done
fi

exit 0