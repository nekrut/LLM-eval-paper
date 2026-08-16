#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# 2. Reference indexing (once)
REF=data/ref/chrM.fa
if [ ! -f "$REF.fai" ] || [ ! -f "${REF}.amb" ]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
    BAM="results/${sample}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="results/${sample}.vcf.gz"
    TBI="${VCF_GZ}.tbi"
    RAW_FQ1="data/raw/${sample}_1.fq.gz"
    RAW_FQ2="data/raw/${sample}_2.fq.gz"

    # 3 & 4. Alignment and sorting (idempotent via BAM existence)
    if [ ! -f "$BAM" ] || [ "$RAW_FQ1" -nt "$BAM" ] || [ "$RAW_FQ2" -nt "$BAM" ]; then
        bwa mem -t $THREADS \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" "$RAW_FQ1" "$RAW_FQ2" | \
            samtools sort -@ $THREADS -o "$BAM" -
    fi

    # 5. BAM indexing (idempotent)
    if [ ! -f "$BAI" ] || [ "$BAM" -nt "$BAI" ]; then
        samtools index -@ $THREADS "$BAM"
    fi

    # 6. Variant calling with lofreq (idempotent via VCF.GZ existence)
    if [ ! -f "$VCF_GZ" ] || [ "$BAM" -nt "$VCF_GZ" ]; then
        VCF_TMP="results/${sample}.vcf.tmp"
        lofreq call-parallel --pp-threads $THREADS -f "$REF" -o "$VCF_TMP" "$BAM"
        
        # 7. Compression and indexing (idempotent)
        if [ ! -f "$TBI" ] || [ "$VCF_TMP" -nt "$TBI" ]; then
            bgzip -c "$VCF_TMP" > "$VCF_GZ"
            tabix -p vcf "$VCF_GZ"
            rm -f "$VCF_TMP"
        else
            rm -f "$VCF_TMP"
        fi
    fi
done

# 8. Collapse step
COLLAPSED="results/collapsed.tsv"
HEADER="sample	chrom	pos	ref	alt	af"

# Check if collapsed file exists and is newer than all VCF.GZ files
need_collapse=0
if [ ! -f "$COLLAPSED" ]; then
    need_collapse=1
else
    for sample in "${SAMPLES[@]}"; do
        VCF_GZ="results/${sample}.vcf.gz"
        if [ "$VCF_GZ" -nt "$COLLAPSED" ]; then
            need_collapse=1
            break
        fi
    done
fi

if [ $need_collapse -eq 1 ]; then
    echo -e "$HEADER" > "$COLLAPSED"
    for sample in "${SAMPLES[@]}"; do
        VCF_GZ="results/${sample}.vcf.gz"
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$COLLAPSED"
    done
fi