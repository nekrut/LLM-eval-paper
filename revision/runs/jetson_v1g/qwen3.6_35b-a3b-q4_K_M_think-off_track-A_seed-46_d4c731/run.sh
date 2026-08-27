#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"

mkdir -p results

# Step 2: Reference indexing (idempotent)
if [ ! -f "data/ref/chrM.fa.fai" ]; then
    samtools faidx "$REF"
fi
if [ ! -f "data/ref/chrM.fa.amb" ]; then
    bwa index "$REF"
fi

# Step 3-7: Per-sample processing
for sample in "${SAMPLES[@]}"; do
    BAM="results/${sample}.bam"
    BAI="${BAM}.bai"
    VCF="results/${sample}.vcf"
    VCFGZ="${VCF}.gz"
    TBI="${VCFGZ}.tbi"

    # Step 3-4: Alignment and sorting
    if [ ! -f "$BAM" ] || [ "data/raw/${sample}_1.fq.gz" -nt "$BAM" ] || [ "data/raw/${sample}_2.fq.gz" -nt "$BAM" ]; then
        bwa mem -t $THREADS \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ $THREADS -o "$BAM" -
    fi

    # Step 5: BAM indexing
    if [ ! -f "$BAI" ] || [ "$BAM" -nt "$BAI" ]; then
        samtools index -@ $THREADS "$BAM"
    fi

    # Step 6: Variant calling with lofreq
    if [ ! -f "$VCFGZ" ] || [ "$BAM" -nt "$VCFGZ" ]; then
        lofreq call-parallel --pp-threads $THREADS --verbose \
            --ref "$REF" \
            --out "$VCF" \
            --sig \
            --bonf \
            "$BAM"
        
        # Step 7: VCF compression and indexing
        bgzip -f "$VCF"
        tabix -p vcf "$VCFGZ"
    fi
done

# Step 8: Collapse step
COLLAPSED="results/collapsed.tsv"
HEADER="sample	chrom	pos	ref	alt	af"

# Check if collapsed file needs rebuilding
NEED_REBUILD=false
for sample in "${SAMPLES[@]}"; do
    VCFGZ="results/${sample}.vcf.gz"
    if [ ! -f "$COLLAPSED" ] || [ "$VCFGZ" -nt "$COLLAPSED" ]; then
        NEED_REBUILD=true
        break
    fi
done

if [ "$NEED_REBUILD" = true ]; then
    {
        echo -e "$HEADER"
        for sample in "${SAMPLES[@]}"; do
            VCFGZ="results/${sample}.vcf.gz"
            if [ -f "$VCFGZ" ]; then
                bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "$VCFGZ"
            fi
        done
    } > "$COLLAPSED"
fi