#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Step 2: Reference indexing (idempotent)
REF=data/ref/chrM.fa
if [ ! -f "${REF}.fai" ] || [ ! -f "${REF}.amb" ]; then
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
    FASTQ1="data/raw/${sample}_1.fq.gz"
    FASTQ2="data/raw/${sample}_2.fq.gz"
    
    need_work=0
    if [ ! -f "$BAM" ] || [ ! -f "$BAI" ] || [ ! -f "$VCF_GZ" ] || [ ! -f "$TBI" ]; then
        need_work=1
    else
        # Check if inputs are newer than outputs
        for out in "$BAM" "$BAI" "$VCF_GZ" "$TBI"; do
            if [ "$FASTQ1" -nt "$out" ] || [ "$FASTQ2" -nt "$out" ]; then
                need_work=1
                break
            fi
        done
    fi

    if [ "$need_work" -eq 0 ]; then
        continue
    fi

    # Step 3 & 4: Alignment and sorting
    bwa mem -t $THREADS \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        "$REF" \
        "$FASTQ1" "$FASTQ2" | \
        samtools sort -@ $THREADS -o "$BAM" -

    # Step 5: BAM indexing
    samtools index -@ $THREADS "$BAM"

    # Step 6: Variant calling with lofreq
    VCF="results/${sample}.vcf"
    if [ ! -f "$VCF" ] || [ "$BAM" -nt "$VCF" ]; then
        lofreq call-parallel --pp-threads $THREADS -f "$REF" -o "$VCF" "$BAM"
    fi

    # Step 7: VCF compression and indexing
    if [ ! -f "$VCF_GZ" ] || [ "$VCF" -nt "$VCF_GZ" ]; then
        bgzip -c "$VCF" > "$VCF_GZ"
        tabix -p vcf "$VCF_GZ"
        rm -f "$VCF"
    fi
done

# Step 8: Collapse step
COLLAPSED="results/collapsed.tsv"
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

if [ "$need_collapse" -eq 1 ]; then
    # Write header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$COLLAPSED"
    
    # Append data for each sample
    for sample in "${SAMPLES[@]}"; do
        VCF_GZ="results/${sample}.vcf.gz"
        if [ -f "$VCF_GZ" ]; then
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCF_GZ" >> "$COLLAPSED"
        fi
    done
fi