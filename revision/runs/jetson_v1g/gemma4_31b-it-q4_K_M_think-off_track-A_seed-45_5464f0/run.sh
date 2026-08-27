#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
OUTDIR="results"

mkdir -p "$OUTDIR"

# 2. Reference indexing
if [[ ! -f "${REF}.fai" ]]; then
    samtools faidx "$REF"
fi

if [[ ! -f "${REF}.bwt" ]]; then
    bwa index "$REF"
fi

for SAMPLE in "${SAMPLES[@]}"; do
    BAM="$OUTDIR/${SAMPLE}.bam"
    BAI="$BAM.bai"
    VCF_GZ="$OUTDIR/${SAMPLE}.vcf.gz"
    VCF_TBI="$VCF_GZ.tbi"
    
    # 3 & 4. Alignment and Sort
    if [[ ! -f "$BAM" ]]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tLB:${SAMPLE}\tPL:ILLUMINA" \
            "$REF" "data/raw/${SAMPLE}_1.fq.gz" "data/raw/${SAMPLE}_2.fq.gz" | \
            samtools sort -@ "$THREADS" -o "$BAM"
    fi

    # 5. BAM Indexing
    if [[ ! -f "$BAI" ]]; then
        samtools index -@ "$THREADS" "$BAM"
    fi

    # 6 & 7. Variant calling and compression
    if [[ ! -f "$VCF_TBI" ]]; then
        lofreq call-parallel --pp-threads "$THREADS" \
            --ref "$REF" \
            --out "$OUTDIR/${SAMPLE}.vcf" \
            "$BAM"
        
        bgzip -c "$OUTDIR/${SAMPLE}.vcf" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "$OUTDIR/${SAMPLE}.vcf"
    fi
done

# 8. Collapse step
COLLAPSED="$OUTDIR/collapsed.tsv"
NEEDS_REBUILD=false

if [[ ! -f "$COLLAPSED" ]]; then
    NEEDS_REBUILD=true
else
    for SAMPLE in "${SAMPLES[@]}"; do
        if [[ "$OUTDIR/${SAMPLE}.vcf.gz" -nt "$COLLAPSED" ]]; then
            NEEDS_REBUILD=true
            break
        fi
    done
fi

if [ "$NEEDS_REBUILD" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for SAMPLE in "${SAMPLES[@]}"; do
        bcftools query -f "${SAMPLE}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$OUTDIR/${SAMPLE}.vcf.gz" >> "$COLLAPSED"
    done
fi