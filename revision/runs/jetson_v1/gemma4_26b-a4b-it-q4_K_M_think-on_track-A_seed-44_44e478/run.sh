#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi

if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

for s in "${SAMPLES[@]}"; do
    FQ1="data/raw/${s}_1.fq.gz"
    FQ2="data/raw/${s}_2.fq.gz"
    BAM="$RESULTS_DIR/${s}.bam"
    VCF_GZ="$RESULTS_DIR/${s}.vcf.gz"
    VCF_TBI="$RESULTS_DIR/${s}.vcf.gz.tbi"

    if ! { [ -f "$VCF_TBI" ] && [ "$VCF_TBI" -nt "$FQ1" ] && [ "$VCF_TBI" -nt "$FQ2" ] && [ "$VCF_TBI" -nt "$REF" ]; }; then
        RG_STR="@RG\tID:${s}\tSM:${s}\tLB:${s}\tPL:ILLUMINA"
        
        bwa mem -t "$THREADS" -R "$RG_STR" "$REF" "$FQ1" "$FQ2" | \
            samtools sort -@ "$THREADS" -o "$BAM"
        
        samtools index -@ "$THREADS" "$BAM"
        
        VCF_TMP="$RESULTS_DIR/${s}.vcf"
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" "$BAM" > "$VCF_TMP"
        
        bgzip -c "$VCF_TMP" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm "$VCF_TMP"
    fi
done

NEEDS_COLLAPSE=false
if [ ! -f "$RESULTS_DIR/collapsed.tsv" ]; then
    NEEDS_COLLAPSE=true
else
    for s in "${SAMPLES[@]}"; do
        if [ "$RESULTS_DIR/${s}.vcf.gz" -nt "$RESULTS_DIR/collapsed.tsv" ]; then
            NEEDS_COLLAPSE=true
            break
        fi
    done
fi

if [ "$NEEDS_COLLAPSE" = true ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$RESULTS_DIR/collapsed.tsv"
    for s in "${SAMPLES[@]}"; do
        bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$RESULTS_DIR/${s}.vcf.gz" >> "$RESULTS_DIR/collapsed.tsv"
    done
fi

exit 0