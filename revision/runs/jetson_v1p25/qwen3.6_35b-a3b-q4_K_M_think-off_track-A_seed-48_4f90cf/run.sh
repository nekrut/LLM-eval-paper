#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Step 2: Reference indexing (idempotent)
REF=data/ref/chrM.fa
if [ ! -f "${REF}.fai" ] || [ ! -f "$(echo ${REF} | sed 's/.fa$//').amb" ]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

# Step 3-7: Per-sample processing
for sample in "${SAMPLES[@]}"; do
    BAM="results/${sample}.bam"
    BAI="${BAM}.bai"
    VCF_GZ="results/${sample}.vcf.gz"
    TBI="${VCF_GZ}.tbi"

    # Skip if all outputs exist and are newer than inputs
    if [ -f "$BAI" ] && [ -f "$TBI" ]; then
        # Check if any input is newer
        need_rebuild=0
        for fq in "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz"; do
            if [ ! -f "$fq" ] || [ "$fq" -nt "$BAI" ]; then
                need_rebuild=1
                break
            fi
        done
        if [ "$REF" -nt "$BAI" ]; then
            need_rebuild=1
        fi
        
        if [ "$need_rebuild" -eq 0 ]; then
            continue
        fi
    fi

    # Step 3 & 4: Alignment and sorting
    bwa mem -t $THREADS \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        "$REF" \
        "data/raw/${sample}_1.fq.gz" \
        "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ $THREADS -o "$BAM" -

    # Step 5: BAM indexing
    samtools index -@ $THREADS "$BAM"

    # Step 6: Variant calling with lofreq
    VCF="results/${sample}.vcf"
    if [ ! -f "$VCF_GZ" ] || [ "$BAM" -nt "$VCF_GZ" ]; then
        lofreq call-parallel --pp-threads $THREADS -f "$REF" -o "$VCF" "$BAM"
        
        # Step 7: Compress and index VCF
        bgzip -c "$VCF" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm -f "$VCF"
    fi
done

# Step 8: Collapse step
COLLAPSED="results/collapsed.tsv"
need_collapsed=0
for sample in "${SAMPLES[@]}"; do
    if [ ! -f "results/${sample}.vcf.gz" ] || [ ! -f "results/${sample}.vcf.gz.tbi" ]; then
        need_collapsed=1
        break
    fi
done

if [ "$need_collapsed" -eq 0 ] && [ -f "$COLLAPSED" ]; then
    # Check if any VCF is newer than collapsed TSV
    for sample in "${SAMPLES[@]}"; do
        if [ "results/${sample}.vcf.gz" -nt "$COLLAPSED" ]; then
            need_collapsed=1
            break
        fi
    done
fi

if [ "$need_collapsed" -eq 1 ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$COLLAPSED"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz" >> "$COLLAPSED"
    done
fi